import Foundation
import Testing
import WebKit
@testable import Pontoon

@Suite("Install identity", .serialized, .timeLimit(.minutes(1))) @MainActor
struct InstallIdentityTests {

    @Test
    func reinstallingSameNamespaceDoesNotCrashAndRewiresThePage() async throws {
        let harness = WebViewHarness()
        let first = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction(name: "which")
        }
        let second = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            ClosureNativeFunction("which") { (_: EchoParameters, _) in
                .success(EchoResult(echoed: "second"))
            }
        }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("return await window.test.which({ text: 'x' });")
        #expect(result["echoed"] as? String == "second")
        #expect(!first.isInstalled)
        #expect(second.isInstalled)
    }

    @Test
    func staleBridgeUninstallLeavesTheLiveOneAlone() async throws {
        let harness = WebViewHarness()
        let first = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        let second = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        first.uninstall()

        let result = try await harness.dictionary("return await window.test.echo({ text: 'alive' });")
        #expect(result["echoed"] as? String == "alive")
        #expect(second.isInstalled)
    }

    @Test
    func uninstallIsIdempotent() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        bridge.uninstall()
        bridge.uninstall()
        #expect(!bridge.isInstalled)
    }

}

@Suite("Hostile page", .serialized, .timeLimit(.minutes(1))) @MainActor
struct HostilePageTests {

    @Test
    func pollutedToJSONCannotRewriteOutboundArguments() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            window.seen = [];
            Object.prototype.toJSON = function () {
                window.seen.push(1);
                return { text: 'REWRITTEN' };
            };
            const echoed = await window.test.echo({ text: 'original' });
            delete Object.prototype.toJSON;
            return {
                echoed: echoed.echoed,
                seen: window.seen.length,
                restored: typeof Object.prototype.toJSON
            };
            """
        )
        #expect(result["echoed"] as? String == "original")
        #expect(result["seen"] as? Int == 0)
    }

    @Test
    func prototypePollutionDoesNotAnswerSwiftCalls() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            Object.prototype.onPaymentConfirmed = async function () {
                return { echoed: 'FORGED' };
            };
            """
        ))

        let error = await captureError { try await bridge.call("onPaymentConfirmed") }
        guard case .functionNotFound = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func occupiedNamespaceIsNotAdopted() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(),
            injecting: .immediately
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: "window.test = { echo: () => 'HIJACKED' };"))
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(),
            injecting: .immediately
        ) {
            EchoFunction()
        }

        let result = try await harness.dictionary("""
            const echoed = await window.test.echo({ text: 'real' });
            return { echoed: typeof echoed === 'string' ? echoed : echoed.echoed };
            """
        )
        #expect(result["echoed"] as? String == "real")
    }

    @Test
    func unserializableArgumentsRejectInsteadOfThrowingSynchronously() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            const cyclic = { text: 'x' };
            cyclic.self = cyclic;
            let threwSynchronously = 0;
            let rejected = 0;
            let promise = null;
            try { promise = window.test.echo(cyclic); } catch (error) { threwSynchronously = 1; }
            if (promise) { try { await promise; } catch (error) { rejected = 1; } }
            return { threwSynchronously: threwSynchronously, rejected: rejected };
            """
        )
        #expect(result["threwSynchronously"] as? Int == 0)
        #expect(result["rejected"] as? Int == 1)
    }

    @Test
    func unserializableResolveFails() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.test.cyclic = async function () {
                const value = { name: 'x' };
                value.self = value;
                return value;
            };
            """
        ))

        let error = await captureError { try await bridge.call("cyclic", as: EchoResult.self) }
        #expect(error is JSCallError)
    }

    @Test
    func protoKeyInParametersDoesNotPolluteThePage() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.test.inspect = async function (payload) {
                return {
                    echoed: [
                        Object.prototype.hasOwnProperty.call(payload, '__proto__') ? 'own' : 'not-own',
                        ({}).polluted === true ? 'POLLUTED' : 'clean'
                    ].join(',')
                };
            };
            """
        ))

        struct Payload: Encodable {
            let value: [String: [String: Bool]]
            func encode(to encoder: any Encoder) throws {
                try value.encode(to: encoder)
            }
        }
        let result = try await bridge.call(
            "inspect",
            parameters: Payload(value: ["__proto__": ["polluted": true]]),
            as: EchoResult.self
        )
        #expect(result.echoed.hasSuffix("clean"))
    }

}

@Suite("Namespace validation") @MainActor
struct NamespaceValidationTests {

    @Test
    func rejectsReservedPrefixForNamespace() {
        #expect(throws: BridgeSetupError.reservedNamespace("_pontoonInternal")) {
            try Fixture.makeBridge(namespace: "_pontoonInternal") { EchoFunction() }
        }
    }

    @Test(arguments: ["myApp", "bridge", "app$1", "_private"])
    func acceptsOrdinaryNamespaces(_ namespace: String) throws {
        let bridge = try Fixture.makeBridge(namespace: namespace) { EchoFunction() }
        #expect(bridge.namespace == namespace)
    }

}

@Suite("Observer contract") @MainActor
struct ObserverContractTests {

    @Test
    func failedNativeCallCarriesFunctionName() async throws {
        let observer = RecordingObserver()
        let bridge = try Fixture.makeBridge { EchoFunction() }
        bridge.observer = observer

        _ = await captureError {
            try await bridge.route(Fixture.makeRequest(function: "missing"))
        }
        #expect(observer.events.count == 1)
        #expect(observer.events.first?.functionName == "missing")
    }

    @Test
    func exactlyOneTerminalEventPerCall() async throws {
        let observer = RecordingObserver()
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["unexpected": true])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)
        bridge.observer = observer

        _ = await captureError { try await bridge.call("fn", as: EchoResult.self) }

        let terminal = observer.names.filter { $0.hasPrefix("jsCallFinished") || $0 == "jsCallFailed" }
        #expect(terminal.count == 1)
        #expect(terminal.first == "jsCallFailed")
    }

    @Test
    func eventsOfOneCallShareAnIdentifier() async throws {
        let observer = RecordingObserver()
        let evaluator = MockJSEvaluator()
        evaluator.respondResolved(["echoed": "hi"])
        let bridge = try Fixture.makeBridge(evaluator: evaluator)
        bridge.observer = observer

        _ = try await bridge.call("first", as: EchoResult.self)
        _ = try await bridge.call("second", as: EchoResult.self)

        let ids = Set(observer.events.map(\.callID))
        #expect(observer.events.count == 4)
        #expect(ids.count == 2)
    }

}
