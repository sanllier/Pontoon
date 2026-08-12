import Testing
@testable import Pontoon

@Suite("BridgeObserver") @MainActor
struct BridgeObserverTests {

    @Test
    func reportsSuccessfulNativeCall() async throws {
        let observer = RecordingObserver()
        let bridge = try Fixture.makeBridge { EchoFunction() }
        bridge.observer = observer

        _ = try await bridge.route(
            Fixture.makeRequest(function: "echo", parametersJSON: #"{"text":"hi"}"#)
        )
        #expect(observer.names == ["nativeCallStarted", "nativeCallFinished.resolved"])
    }

    @Test
    func reportsRejectedNativeCall() async throws {
        let observer = RecordingObserver()
        let bridge = try Fixture.makeBridge { RejectingFunction() }
        bridge.observer = observer

        _ = try await bridge.route(Fixture.makeRequest(function: "reject"))
        #expect(observer.names == ["nativeCallStarted", "nativeCallFinished.rejected"])
    }

    @Test
    func reportsRoutingFailure() async throws {
        let observer = RecordingObserver()
        let bridge = try Fixture.makeBridge { EchoFunction() }
        bridge.observer = observer

        _ = await captureError {
            try await bridge.route(Fixture.makeRequest(function: "missing"))
        }
        #expect(observer.names == ["nativeCallFailed"])
    }

    @Test
    func reportsJSCall() async throws {
        let observer = RecordingObserver()
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["echoed": "hi"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)
        bridge.observer = observer

        _ = try await bridge.call("fn", as: EchoResult.self)
        #expect(observer.names == ["jsCallStarted", "jsCallFinished.resolved"])
    }

    @Test
    func reportsJSCallFailure() async throws {
        let observer = RecordingObserver()
        let evaluator = MockJSEvaluator()
        evaluator.respondFunctionNotFound()
        let bridge = try Fixture.makeBridge(evaluator: evaluator)
        bridge.observer = observer

        _ = await captureError { try await bridge.call("fn") }
        #expect(observer.names == ["jsCallStarted", "jsCallFailed"])
    }

    @Test
    func reportsDecodingFailureOfJSResult() async throws {
        let observer = RecordingObserver()
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["unexpected": true])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)
        bridge.observer = observer

        _ = await captureError { try await bridge.call("fn", as: EchoResult.self) }
        #expect(observer.names == ["jsCallStarted", "jsCallFailed"])
    }

    @Test
    func observerIsHeldWeakly() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        do {
            let observer = RecordingObserver()
            bridge.observer = observer
            #expect(bridge.observer != nil)
        }
        #expect(bridge.observer == nil)
    }

}
