import Foundation
import Testing
import WebKit
@testable import Pontoon

@Suite("Integration", .serialized, .timeLimit(.minutes(1))) @MainActor
struct BridgeIntegrationTests {

    @Test
    func pageCallsNativeFunctionAndGetsPayload() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary(
            "return await window.test.echo({ text: 'hi', count: 2 });"
        )
        #expect(result["echoed"] as? String == "hi")
        #expect(bridge.isInstalled)
    }

    @Test
    func bridgeExistsBeforePageScriptsRun() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(head: """
            window.captured = {
                hasBridge: typeof window.test === 'object',
                hasEcho: typeof window.test.echo === 'function',
                hasToken: typeof window.test._pontoonToken === 'string'
            };
            """
        ))

        let captured = try await harness.dictionary("return window.captured;")
        #expect(captured["hasBridge"] as? Bool == true)
        #expect(captured["hasEcho"] as? Bool == true)
        #expect(captured["hasToken"] as? Bool == true)
    }

    @Test
    func roundTripsUnicodeAndQuotes() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary(
            #"return await window.test.echo({ text: "он сказал \"да\"; alert(1)\n\\ 🌉" });"#
        )
        #expect(result["echoed"] as? String == "он сказал \"да\"; alert(1)\n\\ 🌉")
    }

    @Test
    func nativeFailureArrivesAsPayloadNotError() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { RejectingFunction() }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            try {
                await window.test.reject();
                return { outcome: 'resolved' };
            } catch (error) {
                return {
                    outcome: 'rejected',
                    isError: error instanceof Error,
                    reason: error.reason
                };
            }
            """
        )
        #expect(result["outcome"] as? String == "rejected")
        #expect(result["isError"] as? Bool == false)
        #expect(result["reason"] as? String == "nope")
    }

    @Test
    func bridgeFailureArrivesAsPontoonBridgeError() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            try {
                await window.test.echo({ count: 1 });
                return { outcome: 'resolved' };
            } catch (error) {
                return {
                    outcome: 'rejected',
                    name: error.name,
                    code: error.code,
                    message: error.message
                };
            }
            """
        )
        #expect(result["outcome"] as? String == "rejected")
        #expect(result["name"] as? String == "PontoonBridgeError")
        #expect(result["code"] as? String == "invalidArguments")
        #expect(result["message"] as? String == "Invalid arguments")
    }

    @Test
    func pageCannotOverwriteNativeWrappers() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())

        let result = try await harness.dictionary("""
            const original = window.test.echo;
            try { window.test.echo = () => 'hijacked'; } catch (error) {}
            try { window.test = { echo: () => 'hijacked' }; } catch (error) {}
            try { delete window.test.echo; } catch (error) {}
            const echoed = await window.test.echo({ text: 'still native' });
            return {
                sameFunction: window.test.echo === original,
                echoed: echoed.echoed
            };
            """
        )
        #expect(result["sameFunction"] as? Bool == true)
        #expect(result["echoed"] as? String == "still native")
    }

    @Test
    func pageCanStillExtendTheNamespace() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(head: """
            window.test.onEvent = async function (payload) {
                return { echoed: payload.text + '!' };
            };
            """
        ))

        let result = try await bridge.call(
            "onEvent",
            parameters: EchoParameters(text: "hi", count: nil),
            as: EchoResult.self
        )
        #expect(result == EchoResult(echoed: "hi!"))
    }

    @Test
    func swiftCallReceivesTypedRejection() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(head: """
            window.test.failing = async function () {
                const error = new Error('page said no');
                error.name = 'PageError';
                throw error;
            };
            """
        ))

        struct JSError: Decodable, Equatable {
            var name: String
            var message: String
        }
        let result = try await bridge.call("failing", as: JSVoid.self, rejectingAs: JSError.self)
        #expect(result.rejectedValue == JSError(name: "PageError", message: "page said no"))
    }

    @Test
    func swiftCallReportsMissingFunction() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())

        let error = await captureError { try await bridge.call("neverDefined") }
        guard case .functionNotFound = try #require(error as? JSCallError) else {
            Issue.record("unexpected error \(String(describing: error))")
            return
        }
    }

    @Test
    func swiftCallAwaitsSlowPromise() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(head: """
            window.test.slow = async function (payload) {
                await new Promise((resolve) => setTimeout(resolve, 150));
                return { echoed: payload.text };
            };
            """
        ))

        let result = try await bridge.call(
            "slow",
            parameters: EchoParameters(text: "waited", count: nil),
            as: EchoResult.self
        )
        #expect(result == EchoResult(echoed: "waited"))
    }

    @Test
    func concurrentCallsDoNotCrossWires() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(head: """
            window.test.delayedEcho = async function (payload) {
                await new Promise((resolve) => setTimeout(resolve, payload.count));
                return { echoed: payload.text };
            };
            """
        ))

        async let first = bridge.call(
            "delayedEcho",
            parameters: EchoParameters(text: "slow", count: 120),
            as: EchoResult.self
        )
        async let second = bridge.call(
            "delayedEcho",
            parameters: EchoParameters(text: "fast", count: 10),
            as: EchoResult.self
        )
        let results = try await [first, second]
        #expect(results[0] == EchoResult(echoed: "slow"))
        #expect(results[1] == EchoResult(echoed: "fast"))
    }

    @Test
    func immediateInjectionWorksOnLoadedPage() async throws {
        let harness = WebViewHarness()
        try await harness.load(TestHTML.page())
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin(), injecting: .immediately) {
            EchoFunction()
        }

        let result = try await harness.dictionary("return await window.test.echo({ text: 'late' });")
        #expect(result["echoed"] as? String == "late")
    }

    @Test
    func subframesAreExcludedByDefault() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page(body: #"<iframe id="child" srcdoc="<html></html>"></iframe>"#))

        let result = try await harness.dictionary("""
            const frame = document.getElementById('child');
            await new Promise((resolve) => {
                if (frame.contentDocument && frame.contentDocument.readyState === 'complete') { resolve(); }
                else { frame.addEventListener('load', resolve); }
            });
            return {
                parentHasBridge: typeof window.test === 'object',
                childHasBridge: typeof frame.contentWindow.test === 'object'
            };
            """
        )
        #expect(result["parentHasBridge"] as? Bool == true)
        #expect(result["childHasBridge"] as? Bool == false)
    }

    @Test
    func subframesReachTheBridgeWhenPolicyAllows() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .anyOrigin(allowsSubframes: true)
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(body: #"<iframe id="child" srcdoc="<html></html>"></iframe>"#))

        let result = try await harness.dictionary("""
            const frame = document.getElementById('child');
            await new Promise((resolve) => {
                if (frame.contentDocument && frame.contentDocument.readyState === 'complete') { resolve(); }
                else { frame.addEventListener('load', resolve); }
            });
            const echoed = await frame.contentWindow.test.echo({ text: 'from frame' });
            return { echoed: echoed.echoed };
            """
        )
        #expect(result["echoed"] as? String == "from frame")
    }

    @Test
    func foreignOriginIsRefused() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .init(allowedOrigins: ["https://allowed.test"])
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(), origin: "https://denied.test")

        let result = try await harness.dictionary("""
            try {
                await window.test.echo({ text: 'hi' });
                return { outcome: 'resolved' };
            } catch (error) {
                return { outcome: 'rejected', code: error.code };
            }
            """
        )
        #expect(result["outcome"] as? String == "rejected")
        #expect(result["code"] as? String == "disallowedFrame")
    }

    @Test
    func allowedOriginPassesThrough() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(
            namespace: "test",
            securityPolicy: .init(allowedOrigins: ["https://allowed.test"])
        ) {
            EchoFunction()
        }
        try await harness.load(TestHTML.page(), origin: "https://allowed.test")

        let result = try await harness.dictionary("return await window.test.echo({ text: 'hi' });")
        #expect(result["echoed"] as? String == "hi")
    }

    @Test
    func bridgeSurvivesNavigation() async throws {
        let harness = WebViewHarness()
        _ = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())
        try await harness.load(TestHTML.page(body: "<p>second document</p>"))

        let result = try await harness.dictionary("return await window.test.echo({ text: 'after nav' });")
        #expect(result["echoed"] as? String == "after nav")
    }

    @Test
    func uninstalledBridgeStopsAnsweringThePage() async throws {
        let harness = WebViewHarness()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        try await harness.load(TestHTML.page())
        _ = try await harness.run("return await window.test.echo({ text: 'before' });")

        bridge.uninstall()
        #expect(!bridge.isInstalled)

        let result = try await harness.dictionary("""
            try {
                await window.test.echo({ text: 'after' });
                return { outcome: 'resolved' };
            } catch (error) {
                return { outcome: 'rejected' };
            }
            """
        )
        #expect(result["outcome"] as? String == "rejected")
    }

    @Test
    func observerSeesBothDirections() async throws {
        let harness = WebViewHarness()
        let observer = RecordingObserver()
        let bridge = try harness.webView.installBridge(namespace: "test", securityPolicy: .anyOrigin()) { EchoFunction() }
        bridge.observer = observer
        try await harness.load(TestHTML.page(head: """
            window.test.ping = async function () { return { echoed: 'pong' }; };
            """
        ))

        _ = try await harness.run("return await window.test.echo({ text: 'hi' });")
        _ = try await bridge.call("ping", as: EchoResult.self)

        #expect(observer.names == [
            "nativeCallStarted",
            "nativeCallFinished.resolved",
            "jsCallStarted",
            "jsCallFinished.resolved"
        ])
    }

}
