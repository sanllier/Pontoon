import Foundation
import Testing
@testable import Pontoon

@Suite("Bridge routing") @MainActor
struct BridgeRoutingTests {

    @Test
    func resolvesWithEncodedPayload() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let reply = try await bridge.route(
            Fixture.makeRequest(function: "echo", parametersJSON: #"{"text":"hi"}"#)
        )
        #expect(Fixture.resolved(reply)["echoed"] as? String == "hi")
    }

    @Test
    func failureIsWrappedIntoRejectionEnvelope() async throws {
        let bridge = try Fixture.makeBridge { RejectingFunction() }
        let reply = try await bridge.route(Fixture.makeRequest(function: "reject"))
        let envelope = Fixture.rejected(reply)
        #expect(envelope["type"] as? String == "rejection")
        #expect((envelope["payload"] as? [String: Any])?["reason"] as? String == "nope")
    }

    @Test
    func rejectsMessageForAnotherNamespace() async throws {
        let bridge = try Fixture.makeBridge(namespace: "test") { EchoFunction() }
        let error = await captureError {
            try await bridge.route(Fixture.makeRequest(namespace: "other", function: "echo"))
        }
        guard case .brokenNativeFunctionRequest = try #require(error as? BridgeError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func rejectsBodyThatIsNotABridgeMessage() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let bodies: [Any?] = [nil, "not a dictionary", 42, ["function": "echo"], ["parameters": [:]]]
        for body in bodies {
            let request = Bridge.Request(
                name: "test",
                body: body,
                isMainFrame: true,
                origin: "https://pontoon.test"
            )
            let error = await captureError { try await bridge.route(request) }
            guard case .brokenNativeFunctionRequest = try #require(error as? BridgeError) else {
                Issue.record("unexpected error for \(String(describing: body))")
                continue
            }
        }
    }

    @Test
    func reportsUnknownFunction() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let error = await captureError {
            try await bridge.route(Fixture.makeRequest(function: "missing"))
        }
        guard case .nativeFunctionNotDefined(let name) = try #require(error as? BridgeError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(name == "missing")
    }

    @Test
    func reportsInvalidArgumentsWithUnderlyingError() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let error = await captureError {
            try await bridge.route(
                Fixture.makeRequest(function: "echo", parametersJSON: #"{"count":1}"#)
            )
        }
        guard case .nativeFunctionInvalidArguments(let function, let underlying) =
            try #require(error as? BridgeError)
        else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(function == "echo")
        #expect(underlying is DecodingError)
    }

    @Test
    func reportsUnserializableResponse() async throws {
        let bridge = try Fixture.makeBridge { UnserializableFunction() }
        let error = await captureError {
            try await bridge.route(Fixture.makeRequest(function: "broken"))
        }
        guard case .cannotSerializeResponse(let function, _) = try #require(error as? BridgeError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(function == "broken")
    }

    @Test
    func rejectsSubframeByDefault() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let error = await captureError {
            try await bridge.route(Fixture.makeRequest(
                function: "echo",
                parametersJSON: #"{"text":"hi"}"#,
                isMainFrame: false
            ))
        }
        guard case .requestFromDisallowedFrame(let origin) = try #require(error as? BridgeError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(origin == "https://pontoon.test")
    }

    @Test
    func acceptsSubframeWhenPolicyAllows() async throws {
        let bridge = try Fixture.makeBridge(
            securityPolicy: .anyOrigin(allowsSubframes: true)
        ) {
            EchoFunction()
        }
        let reply = try await bridge.route(Fixture.makeRequest(
            function: "echo",
            parametersJSON: #"{"text":"hi"}"#,
            isMainFrame: false
        ))
        #expect(Fixture.resolved(reply)["echoed"] as? String == "hi")
    }

    @Test
    func rejectsForeignOrigin() async throws {
        let bridge = try Fixture.makeBridge(
            securityPolicy: .init(allowedOrigins: ["https://app.example.com"])
        ) {
            EchoFunction()
        }
        let error = await captureError {
            try await bridge.route(Fixture.makeRequest(
                function: "echo",
                parametersJSON: #"{"text":"hi"}"#,
                origin: "https://evil.example.com"
            ))
        }
        #expect(error is BridgeError)
    }

    @Test
    func encodesBridgeErrorAsEnvelope() throws {
        let json = Bridge.encodeBridgeError(.nativeFunctionNotDefined(function: "missing"))
        let envelope = Fixture.object(json)
        #expect(envelope["type"] as? String == "bridgeError")
        #expect(envelope["code"] as? String == "functionNotDefined")
        #expect(envelope["message"] as? String == "Function is not defined")
    }

    @Test
    func envelopeKeepsNativeDetailsOffThePage() throws {
        struct SecretShape: Decodable {
            var accountNumber: String
        }
        var underlying: (any Error)?
        do { _ = try JSONDecoder().decode(SecretShape.self, from: Data("{}".utf8)) }
        catch { underlying = error }
        let error = BridgeError.nativeFunctionInvalidArguments(
            function: "transfer",
            underlying: try #require(underlying)
        )
        let envelope = Fixture.object(Bridge.encodeBridgeError(error))
        let message = try #require(envelope["message"] as? String)

        #expect(envelope["code"] as? String == "invalidArguments")
        #expect(message == "Invalid arguments")
        #expect(!message.contains("accountNumber"))
        #expect(!message.contains("transfer"))
        #expect(error.description.contains("accountNumber"))
        #expect(error.description.contains("transfer"))
    }

}
