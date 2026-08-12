import Foundation
import WebKit
@testable import Pontoon

struct EchoParameters: Codable, Sendable, Equatable {
    var text: String
    var count: Int?
}

struct EchoResult: Codable, Sendable, Equatable {
    var echoed: String
}

struct EchoFailure: Codable, Sendable, Equatable {
    var reason: String
}

struct FailingEncodable: Encodable, Sendable {

    struct Failure: Error {}

    func encode(to encoder: any Encoder) throws {
        throw Failure()
    }

}

struct EchoFunction: TypedNativeFunction {

    let name: String

    init(name: String = "echo") {
        self.name = name
    }

    func handle(parameters: EchoParameters, bridge: Bridge) async -> NativeFunctionResult {
        .success(EchoResult(echoed: parameters.text))
    }

}

struct RejectingFunction: TypedNativeFunction {

    let name: String

    init(name: String = "reject") {
        self.name = name
    }

    func handle(parameters: JSVoid, bridge: Bridge) async -> NativeFunctionResult {
        .failure(EchoFailure(reason: "nope"))
    }

}

struct UnserializableFunction: TypedNativeFunction {

    let name: String

    init(name: String = "broken") {
        self.name = name
    }

    func handle(parameters: JSVoid, bridge: Bridge) async -> NativeFunctionResult {
        .success(FailingEncodable())
    }

}

@MainActor
final class RecordingObserver: BridgeObserver {

    // MARK: - Public Properties

    private(set) var events: [BridgeEvent] = []

    var names: [String] {
        events.map(\.label)
    }

    // MARK: - Public Methods

    func bridge(_ bridge: Bridge, didReceive event: BridgeEvent) {
        events.append(event)
    }

}

extension BridgeEvent {

    // MARK: - Public Properties

    var label: String {
        switch self {
        case .nativeCallStarted: "nativeCallStarted"
        case .nativeCallFinished(_, _, let outcome, _): "nativeCallFinished.\(outcome)"
        case .nativeCallFailed: "nativeCallFailed"
        case .jsCallStarted: "jsCallStarted"
        case .jsCallFinished(_, _, let outcome, _): "jsCallFinished.\(outcome)"
        case .jsCallFailed: "jsCallFailed"
        }
    }

    var callID: Int {
        switch self {
        case .nativeCallStarted(let id, _): id
        case .nativeCallFinished(let id, _, _, _): id
        case .nativeCallFailed(let id, _, _): id
        case .jsCallStarted(let id, _): id
        case .jsCallFinished(let id, _, _, _): id
        case .jsCallFailed(let id, _, _): id
        }
    }

    var functionName: String? {
        switch self {
        case .nativeCallStarted(_, let function): function
        case .nativeCallFinished(_, let function, _, _): function
        case .nativeCallFailed(_, let function, _): function
        case .jsCallStarted(_, let function): function
        case .jsCallFinished(_, let function, _, _): function
        case .jsCallFailed(_, let function, _): function
        }
    }

}

@MainActor
enum Fixture {

    // MARK: - Public Methods

    static func makeBridge(
        namespace: String = "test",
        securityPolicy: BridgeSecurityPolicy = .anyOrigin(),
        evaluator: any JSEvaluator = MockJSEvaluator(),
        @NativeFunctionsBuilder functions: () -> [any NativeFunction] = { [] }
    ) throws -> Bridge {
        let bridge = try Bridge.make(
            namespace: namespace,
            securityPolicy: securityPolicy,
            functions: functions(),
            evaluator: evaluator
        )
        bridge.didInstall(in: WKUserContentController(), contentWorld: .page)
        return bridge
    }

    static func makeRequest(
        namespace: String = "test",
        function: String = "echo",
        parametersJSON: String = "{}",
        isMainFrame: Bool = true,
        origin: String? = "https://pontoon.test"
    ) -> Bridge.Request {
        let parameters = (try? JSONSerialization.jsonObject(
            with: Data(parametersJSON.utf8),
            options: [.fragmentsAllowed]
        )) ?? [:]
        return .init(
            name: namespace,
            body: ["function": function, "parameters": parameters],
            isMainFrame: isMainFrame,
            origin: origin
        )
    }

    static func resolved(_ reply: Bridge.Reply) -> [String: Any] {
        guard case .resolve(let payload) = reply else { return [:] }
        return payload as? [String: Any] ?? [:]
    }

    static func rejected(_ reply: Bridge.Reply) -> [String: Any] {
        guard case .reject(let json) = reply else { return [:] }
        return object(json)
    }

    static func object(_ json: String) -> [String: Any] {
        let data = json.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

}

@MainActor
func captureError<T>(_ operation: () async throws -> T) async -> (any Error)? {
    do {
        _ = try await operation()
        return nil
    } catch {
        return error
    }
}
