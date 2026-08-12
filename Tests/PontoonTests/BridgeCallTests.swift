import Foundation
import Testing
@testable import Pontoon

@Suite("Bridge call") @MainActor
struct BridgeCallTests {

    @Test
    func passesNamespaceNameAndParametersAsValues() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["echoed": "hi"])
        let bridge = try Fixture.makeBridge(namespace: "myApp", evaluator: evaluator)

        _ = try await bridge.call(
            "onCart",
            parameters: EchoParameters(text: "hi", count: 3),
            as: EchoResult.self
        )

        let invocation = try #require(evaluator.lastInvocation)
        #expect(invocation.namespace == "myApp")
        #expect(invocation.functionName == "onCart")
        let parameters = try #require(invocation.parameters as? [String: Any])
        #expect(parameters["text"] as? String == "hi")
        #expect(parameters["count"] as? Int == 3)
    }

    @Test
    func decodesResolvedPayload() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["echoed": "hi"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let result = try await bridge.call("fn", as: EchoResult.self)
        #expect(result == EchoResult(echoed: "hi"))
    }

    @Test
    func decodesRejectedPayloadInFullForm() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondRejected(["reason": "nope"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let result = try await bridge.call("fn", as: EchoResult.self, rejectingAs: EchoFailure.self)
        #expect(result == .rejected(EchoFailure(reason: "nope")))
        #expect(result.rejectedValue == EchoFailure(reason: "nope"))
        #expect(!result.isResolved)
    }

    @Test
    func shorthandThrowsRejectionWithRawPayload() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondRejected(["reason": "nope"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError {
            try await bridge.call("fn", as: EchoResult.self)
        }
        guard case .rejected(let payloadJSON) = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(Fixture.object(payloadJSON)["reason"] as? String == "nope")
    }

    @Test
    func voidOverloadIgnoresResolvedPayload() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["echoed": "hi"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        try await bridge.call("fn")
        #expect(evaluator.invocations.count == 1)
    }

    @Test
    func voidOverloadStillThrowsOnRejection() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondRejected([:])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError { try await bridge.call("fn") }
        #expect(error is JSCallError)
    }

    @Test
    func parameterlessOverloadSendsEmptyObject() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved([:])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        try await bridge.call("fn")
        #expect((evaluator.lastInvocation?.parameters as? [String: Any])?.isEmpty == true)
    }

    @Test
    func reportsFunctionNotFound() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondFunctionNotFound()
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError { try await bridge.call("fn") }
        guard case .functionNotFound = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func reportsDetachedBridge() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.response = .failure(.evaluatorUnavailable)
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError { try await bridge.call("fn") }
        guard case .bridgeDetached = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func reportsExecutionFailure() async throws {
        struct WebKitFailure: Error {}
        let evaluator = MockJSEvaluator()
        evaluator.response = .failure(.failed(WebKitFailure()))
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError { try await bridge.call("fn") }
        guard case .executionFailed(let underlying) = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(underlying is WebKitFailure)
    }

    @Test
    func reportsInvalidResponse() async throws {
        let responses: [Any?] = [
            nil,
            "not a dictionary",
            ["kind": "somethingElse"],
            ["payload": "{}"],
            ["kind": "resolved"]
        ]
        for response in responses {
            let evaluator = MockJSEvaluator()
            evaluator.response = .success(response)
            let bridge = try Fixture.makeBridge(evaluator: evaluator)

            let error = await captureError { try await bridge.call("fn") }
            guard case .invalidResponse = try #require(error as? JSCallError) else {
                Issue.record("unexpected error for \(String(describing: response))")
                continue
            }
        }
    }

    @Test
    func reportsDecodingFailure() async throws {
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["unexpected": true])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError { try await bridge.call("fn", as: EchoResult.self) }
        guard case .decodingFailed(let underlying) = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(underlying is DecodingError)
    }

    @Test
    func reportsEncodingFailure() async throws {
        let evaluator = MockJSEvaluator()
        let bridge = try Fixture.makeBridge(evaluator: evaluator)

        let error = await captureError {
            try await bridge.call("fn", parameters: FailingEncodable())
        }
        guard case .encodingFailed = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(evaluator.invocations.isEmpty)
    }

}
