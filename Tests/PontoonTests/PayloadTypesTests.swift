import Foundation
import Testing
@testable import Pontoon

@Suite("JSPromiseResult")
struct JSPromiseResultTests {

    @Test
    func exposesResolvedValue() {
        let result = JSPromiseResult<EchoResult, EchoFailure>.resolved(EchoResult(echoed: "hi"))
        #expect(result.resolvedValue == EchoResult(echoed: "hi"))
        #expect(result.rejectedValue == nil)
        #expect(result.isResolved)
    }

    @Test
    func exposesRejectedValue() {
        let result = JSPromiseResult<EchoResult, EchoFailure>.rejected(EchoFailure(reason: "nope"))
        #expect(result.resolvedValue == nil)
        #expect(result.rejectedValue == EchoFailure(reason: "nope"))
        #expect(!result.isResolved)
    }

    @Test
    func comparesByCaseAndValue() {
        typealias Result = JSPromiseResult<EchoResult, EchoFailure>
        #expect(Result.resolved(.init(echoed: "a")) == Result.resolved(.init(echoed: "a")))
        #expect(Result.resolved(.init(echoed: "a")) != Result.resolved(.init(echoed: "b")))
        #expect(Result.resolved(.init(echoed: "a")) != Result.rejected(.init(reason: "a")))
    }

}

@Suite("JSVoid")
struct JSVoidTests {

    @Test
    func encodesToEmptyObject() throws {
        let data = try JSONEncoder().encode(JSVoid.void)
        #expect(String(data: data, encoding: .utf8) == "{}")
    }

    @Test(arguments: ["{}", #"{"unexpected":1}"#, "null", "42", #""text""#])
    func decodesFromAnything(_ json: String) throws {
        let data = try #require(json.data(using: .utf8))
        #expect(throws: Never.self) {
            try JSONDecoder().decode(JSVoid.self, from: data)
        }
    }

}

@Suite("TypedNativeFunction") @MainActor
struct TypedNativeFunctionTests {

    @Test
    func decodesParametersBeforeHandling() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let data = try #require(#"{"text":"hello","count":2}"#.data(using: .utf8))
        let function = EchoFunction()

        let result = try await function.invoke(parametersData: data, bridge: bridge)
        guard case .success(let payload) = result else {
            Issue.record("expected success")
            return
        }
        #expect((payload as? EchoResult)?.echoed == "hello")
    }

    @Test
    func blockFunctionReceivesDecodedParameters() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let function = ClosureNativeFunction("block") { (parameters: EchoParameters, _) in
            .success(EchoResult(echoed: parameters.text.uppercased()))
        }
        let data = try #require(#"{"text":"hi"}"#.data(using: .utf8))

        let result = try await function.invoke(parametersData: data, bridge: bridge)
        guard case .success(let payload) = result else {
            Issue.record("expected success")
            return
        }
        #expect((payload as? EchoResult)?.echoed == "HI")
    }

    @Test
    func emptyResultCarriesJSVoid() async throws {
        guard case .success(let payload) = NativeFunctionResult.empty else {
            Issue.record("expected success")
            return
        }
        #expect(payload is JSVoid)
        let data = try JSONEncoder().encode(payload)
        #expect(String(data: data, encoding: .utf8) == "{}")
    }

    @Test
    func parameterlessBlockFunctionIgnoresPayload() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let function = ClosureNativeFunction("ping") { _ in
            .success(EchoResult(echoed: "pong"))
        }
        let data = try #require(#"{"unexpected":1}"#.data(using: .utf8))

        let result = try await function.invoke(parametersData: data, bridge: bridge)
        guard case .success(let payload) = result else {
            Issue.record("expected success")
            return
        }
        #expect((payload as? EchoResult)?.echoed == "pong")
    }

    @Test
    func parameterlessBlockFunctionRoutesThroughBridge() async throws {
        let bridge = try Fixture.makeBridge {
            ClosureNativeFunction("logout") { _ in .empty }
        }
        let reply = try await bridge.route(Fixture.makeRequest(function: "logout"))
        #expect(Fixture.resolved(reply).isEmpty)
    }

    @Test
    func invalidParametersThrowWithContext() async throws {
        let bridge = try Fixture.makeBridge { EchoFunction() }
        let function = EchoFunction(name: "echo")
        let data = try #require("{}".data(using: .utf8))

        let error = await captureError {
            try await function.invoke(parametersData: data, bridge: bridge)
        }
        guard case .nativeFunctionInvalidArguments(let name, _) = try #require(error as? BridgeError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(name == "echo")
    }

}
