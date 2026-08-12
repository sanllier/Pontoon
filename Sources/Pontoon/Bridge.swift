import WebKit

@MainActor
public final class Bridge {

    // MARK: - Public Properties

    public let namespace: String
    public let securityPolicy: BridgeSecurityPolicy

    public weak var observer: (any BridgeObserver)?

    public private(set) var isInstalled = false

    // MARK: - Constructors

    init(
        caller: JSCaller,
        namespace: String,
        securityPolicy: BridgeSecurityPolicy,
        injectionCode: String,
        functions: [any NativeFunction]
    ) {
        self.caller = caller
        self.namespace = namespace
        self.securityPolicy = securityPolicy
        self.injectionCode = injectionCode
        self.functions = Dictionary(
            functions.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Public Methods

    public func uninstall() {
        guard isInstalled, let userContentController, let contentWorld else { return }
        userContentController.removeScriptMessageHandler(forName: namespace, contentWorld: contentWorld)
        BridgeRegistry.unregister(
            in: userContentController,
            namespace: namespace,
            contentWorld: contentWorld
        )
        detach()
    }

    // MARK: - Internal Properties

    let injectionCode: String

    // MARK: - Internal Methods

    func callFunction<Input: Encodable, Resolved>(
        _ functionName: String,
        parameters: Input,
        decoding: (JSCallOutcome) throws(JSCallError) -> Resolved
    ) async throws(JSCallError) -> Resolved {
        let id = makeCallID()
        report(.jsCallStarted(id: id, function: functionName))
        let startedAt = ContinuousClock().now
        do throws(JSCallError) {
            try guardOutgoingCall(functionName)
            let outcome = try await caller.call(functionName, parameters: parameters)
            let decoded = try decoding(outcome)
            report(.jsCallFinished(
                id: id,
                function: functionName,
                outcome: outcome.observedOutcome,
                duration: ContinuousClock().now - startedAt
            ))
            return decoded
        } catch {
            report(.jsCallFailed(id: id, function: functionName, error: error))
            throw error
        }
    }

    func report(_ event: BridgeEvent) {
        observer?.bridge(self, didReceive: event)
    }

    func guardOutgoingCall(_ functionName: String) throws(JSCallError) {
        guard isInstalled else { throw .bridgeDetached }
        guard functions[functionName] == nil else { throw .functionIsNative(functionName) }
        let origin = caller.currentOrigin
        guard securityPolicy.allows(isMainFrame: true, origin: origin) else {
            throw .documentNotAllowed(origin: origin)
        }
    }

    func makeCallID() -> Int {
        lastCallID += 1
        return lastCallID
    }

    func didInstall(
        in userContentController: WKUserContentController,
        contentWorld: WKContentWorld
    ) {
        self.userContentController = userContentController
        self.contentWorld = contentWorld
        isInstalled = true
    }

    func detach() {
        isInstalled = false
        userContentController = nil
        contentWorld = nil
    }

    // MARK: - Private Properties

    private let caller: JSCaller
    private let functions: [String: any NativeFunction]

    private weak var userContentController: WKUserContentController?
    private var contentWorld: WKContentWorld?
    private var lastCallID = 0

}

extension Bridge {

    // MARK: - Internal Nested

    struct Request {
        var name: String
        var body: Any?
        var isMainFrame: Bool
        var origin: String?

        init(name: String, body: Any?, isMainFrame: Bool, origin: String?) {
            self.name = name
            self.body = body
            self.isMainFrame = isMainFrame
            self.origin = origin
        }

        @MainActor
        init(message: WKScriptMessage) {
            name = message.name
            body = message.body
            isMainFrame = message.frameInfo.isMainFrame
            origin = message.frameInfo.securityOrigin.originString
        }

        var functionName: String? {
            (body as? [String: Any])?["function"] as? String
        }
    }

    enum Reply {
        case resolve(Any)
        case reject(String)
    }

    // MARK: - Internal Methods

    func route(_ request: Request) async throws(BridgeError) -> Reply {
        let id = makeCallID()
        do throws(BridgeError) {
            return try await dispatch(request, id: id)
        } catch {
            report(.nativeCallFailed(id: id, function: request.functionName, error: error))
            throw error
        }
    }

    static func encodeBridgeError(_ error: BridgeError) -> String {
        let envelope = FailureEnvelope(
            type: .bridgeError,
            code: error.code,
            message: error.pageMessage
        )
        guard let data = try? JSONEncoder().encode(envelope),
            let json = String(data: data, encoding: .utf8)
        else {
            return #"{"type":"bridgeError","code":"cannotSerializeResponse"}"#
        }
        return json
    }

}

fileprivate extension Bridge {

    // MARK: - Private Nested

    struct FailureEnvelope: Encodable {
        enum EnvelopeType: String, Encodable {
            case rejection
            case bridgeError
        }

        var type: EnvelopeType
        var payload: (any Encodable)?
        var code: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case type
            case payload
            case code
            case message
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            if let payload { try container.encode(payload, forKey: .payload) }
            try container.encodeIfPresent(code, forKey: .code)
            try container.encodeIfPresent(message, forKey: .message)
        }
    }

    enum SerializationFailure: Error {
        case invalidUTF8
    }

    // MARK: - Private Methods

    func dispatch(_ request: Request, id: Int) async throws(BridgeError) -> Reply {
        guard securityPolicy.allows(isMainFrame: request.isMainFrame, origin: request.origin) else {
            throw .requestFromDisallowedFrame(origin: request.origin ?? "opaque")
        }
        guard request.name == namespace else { throw .brokenNativeFunctionRequest }
        guard let body = request.body as? [String: Any],
            let functionName = body["function"] as? String,
            let parameters = body["parameters"],
            let parametersData = JSONValue.data(from: parameters)
        else {
            throw .brokenNativeFunctionRequest
        }
        guard let function = functions[functionName] else {
            throw .nativeFunctionNotDefined(function: functionName)
        }
        report(.nativeCallStarted(id: id, function: functionName))
        let startedAt = ContinuousClock().now
        let result = try await function.invoke(parametersData: parametersData, bridge: self)
        let reply: Reply
        switch result {
        case .success(let payload):
            reply = .resolve(try Self.value(of: payload, function: functionName))
        case .failure(let payload):
            reply = .reject(try Self.json(
                of: FailureEnvelope(type: .rejection, payload: payload),
                function: functionName
            ))
        }
        report(.nativeCallFinished(
            id: id,
            function: functionName,
            outcome: result.observedOutcome,
            duration: ContinuousClock().now - startedAt
        ))
        return reply
    }

    static func value(of payload: any Encodable, function: String) throws(BridgeError) -> Any {
        let data: Data
        do { data = try JSONEncoder().encode(payload) }
        catch { throw .cannotSerializeResponse(function: function, underlying: error) }
        guard let value = JSONValue.value(from: data) else {
            throw .cannotSerializeResponse(function: function, underlying: SerializationFailure.invalidUTF8)
        }
        return value
    }

    static func json(of envelope: any Encodable, function: String) throws(BridgeError) -> String {
        do {
            let data = try JSONEncoder().encode(envelope)
            guard let json = String(data: data, encoding: .utf8) else {
                throw SerializationFailure.invalidUTF8
            }
            return json
        } catch {
            throw .cannotSerializeResponse(function: function, underlying: error)
        }
    }

}
