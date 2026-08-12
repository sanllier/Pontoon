import Foundation
import Testing
import WebKit
@testable import Pontoon

@Suite("Outbound policy", .serialized, .timeLimit(.minutes(1))) @MainActor
struct OutboundPolicyTests {

    @Test
    func callIsRefusedAfterNavigatingToAForeignOrigin() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: try .init(allowedOrigins: ["https://allowed.test"])
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.test.leak = async function (payload) { return { echoed: payload.text }; };
            """
        ), origin: "https://allowed.test")

        let allowed = try await bridge.call(
            "leak",
            parameters: EchoParameters(text: "fine", count: nil),
            as: EchoResult.self
        )
        #expect(allowed == EchoResult(echoed: "fine"))

        try await harness.load(TestHTML.page(head: """
            window.test = window.test || {};
            window.test.leak = async function (payload) { window.stolen = payload.text; return { echoed: 'ack' }; };
            """
        ), origin: "https://evil.test")

        let error = await captureError {
            try await bridge.call(
                "leak",
                parameters: EchoParameters(text: "Bearer-SECRET", count: nil),
                as: EchoResult.self
            )
        }
        guard case .documentNotAllowed(let origin) = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(origin == "https://evil.test")

        let stolen = try await harness.run("return window.stolen === undefined ? 'none' : window.stolen;")
        #expect(stolen as? String == "none")
    }

    @Test
    func uninstallClosesTheOutgoingDirectionToo() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(head: """
            window.test.ping = async function () { return { echoed: 'pong' }; };
            """
        ))
        _ = try await bridge.call("ping", as: EchoResult.self)

        bridge.uninstall()

        let error = await captureError { try await bridge.call("ping", as: EchoResult.self) }
        guard case .bridgeDetached = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func callingOwnNativeFunctionIsRefused() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page())

        let error = await captureError {
            try await bridge.call(
                "echo",
                parameters: EchoParameters(text: "loop", count: nil),
                as: EchoResult.self
            )
        }
        guard case .functionIsNative(let name) = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
        #expect(name == "echo")
    }

    @Test
    func localFilesAreReachableWhenAllowlisted() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pontoon-file-origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("index.html")
        try TestHTML.page(head: """
            window.captured = null;
            """
        ).write(to: page, atomically: true, encoding: .utf8)

        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: try .init(allowedOrigins: ["file://"])
        ) {
            EchoFunction()
        }
        try await harness.loadFile(page)

        let inbound = try await harness.dictionary("return await window.test.echo({ text: 'from file' });")
        #expect(inbound["echoed"] as? String == "from file")
        #expect(bridge.isInstalled)
    }

    @Test
    func localFilesAreRefusedWhenNotAllowlisted() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pontoon-file-origin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = directory.appendingPathComponent("index.html")
        try TestHTML.page().write(to: page, atomically: true, encoding: .utf8)

        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: try .init(allowedOrigins: ["https://app.example.com"])
        ) {
            EchoFunction()
        }
        try await harness.loadFile(page)

        let result = try await harness.dictionary("""
            try {
                await window.test.echo({ text: 'from file' });
                return { outcome: 'resolved' };
            } catch (error) {
                return { outcome: 'rejected', code: error.code };
            }
            """
        )
        #expect(result["outcome"] as? String == "rejected")
        #expect(result["code"] as? String == "disallowedFrame")
    }

}

@Suite("Shared configuration", .serialized, .timeLimit(.minutes(1))) @MainActor
struct SharedConfigurationTests {

    @Test
    func namespaceCannotBeClaimedByASecondWebView() throws {
        let configuration = WKWebViewConfiguration()
        let first = WKWebView(frame: .zero, configuration: configuration)
        let second = WKWebView(frame: .zero, configuration: configuration)
        let bridge = try first.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }

        #expect(throws: BridgeSetupError.namespaceInUseByAnotherWebView("test")) {
            try second.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        }
        #expect(bridge.isInstalled)
    }

    @Test
    func namespaceIsFreedForOtherWebViewsAfterUninstall() throws {
        let configuration = WKWebViewConfiguration()
        let first = WKWebView(frame: .zero, configuration: configuration)
        let second = WKWebView(frame: .zero, configuration: configuration)
        let bridge = try first.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        bridge.uninstall()

        let replacement = try second.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        #expect(replacement.isInstalled)
        #expect(!bridge.isInstalled)
    }

    @Test
    func reinstallOnTheSameWebViewIsAllowed() throws {
        let webView = WKWebView(frame: .zero, configuration: .init())
        let first = try webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        let second = try webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) {
            EchoFunction()
        }
        #expect(!first.isInstalled)
        #expect(second.isInstalled)
    }

}
