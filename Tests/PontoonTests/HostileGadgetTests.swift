import Foundation
import Testing
import WebKit
@testable import Pontoon

@Suite("Hostile gadgets", .serialized, .timeLimit(.minutes(1))) @MainActor
struct HostileGadgetTests {

    @Test
    func arrayPrototypeToJSONCannotRewriteArguments() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            ClosureNativeFunction("transfer") { (parameters: [String], _) in
                .success(EchoResult(echoed: parameters.joined(separator: ",")))
            }
        }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            Array.prototype.toJSON = function () { return ['attacker-account', '999999']; };
            const echoed = await window.test.transfer(['my-account', '10']);
            delete Array.prototype.toJSON;
            return { echoed: echoed.echoed };
            """
        )
        #expect(result["echoed"] as? String == "my-account,10")
    }

    @Test
    func namespaceCarryingAForeignTokenIsNotAdopted() async throws {
        let harness = WebViewHarness()
        try await harness.load(TestHTML.page(head: """
            window.test = { _pontoonToken: 'guessed', echo: function () { return 'HIJACKED'; } };
            """
        ))
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
    func pageOwnedNamespaceIsNotMistakenForTheBridge() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(),
            injecting: .immediately
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.test = {
                _pontoonToken: 'guessed',
                ping: async function () { return { echoed: 'FORGED' }; }
            };
            """
        ))

        let error = await captureError { try await bridge.call("ping", as: EchoResult.self) }
        guard case .bridgeMissingOnPage = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

}

@Suite("Content world", .serialized, .timeLimit(.minutes(1))) @MainActor
struct ContentWorldTests {

    @Test
    func isolatedWorldHidesTheBridgeFromPageScripts() async throws {
        let harness = WebViewHarness()
        let world = WKContentWorld.world(name: "pontoon-tests")
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(),
            contentWorld: world
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        let visible = try await harness.run("return typeof window.test;")
        #expect(visible as? String == "undefined")

        let handlers = try await harness.run(
            "return typeof (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.test);"
        )
        #expect(handlers as? String == "undefined")

        let inIsolated = try await harness.webView.callAsyncJavaScript(
            "return await window.test.echo({ text: 'isolated' });",
            arguments: [:],
            contentWorld: world
        )
        #expect((inIsolated as? [String: Any])?["echoed"] as? String == "isolated")
    }

}

@Suite("Injection modes", .serialized, .timeLimit(.minutes(1))) @MainActor
struct InjectionModeTests {

    @Test
    func immediatelyAndAtDocumentStartWorksNowAndAfterNavigation() async throws {
        let harness = WebViewHarness()
        try await harness.load(TestHTML.page())
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(),
            injecting: .immediatelyAndAtDocumentStart
        ) {
            EchoFunction()
        }

        let now = try await harness.dictionary("return await window.test.echo({ text: 'now' });")
        #expect(now["echoed"] as? String == "now")

        try await harness.load(TestHTML.page(body: "<p>second</p>"))
        let afterNavigation = try await harness.dictionary("return await window.test.echo({ text: 'later' });")
        #expect(afterNavigation["echoed"] as? String == "later")
    }

    @Test
    func installsAtDocumentStartByDefault() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.captured = typeof window.test.echo === 'function';
            """
        ))

        let captured = try await harness.run("return window.captured;")
        #expect(captured as? Bool == true)
    }

}
