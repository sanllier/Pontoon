import Foundation
import Testing
import WebKit
@testable import Pontoon

@MainActor
final class WebViewHarness {

    // MARK: - Public Properties

    let webView: WKWebView

    // MARK: - Constructors

    init() {
        webView = WKWebView(frame: .init(x: 0, y: 0, width: 320, height: 480), configuration: .init())
        webView.navigationDelegate = navigationWaiter
    }

    // MARK: - Public Methods

    func load(_ html: String, origin: String = "https://pontoon.test") async throws {
        try await navigationWaiter.wait {
            webView.loadHTMLString(html, baseURL: URL(string: origin + "/"))
        }
    }

    func loadFile(_ url: URL) async throws {
        try await navigationWaiter.wait {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    @discardableResult
    func run(_ script: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: [:], contentWorld: .page)
    }

    func dictionary(_ script: String) async throws -> [String: Any] {
        try #require(try await run(script) as? [String: Any])
    }

    // MARK: - Private Properties

    private let navigationWaiter = NavigationWaiter()

}

@MainActor
final class NavigationWaiter: NSObject, WKNavigationDelegate {

    // MARK: - Public Methods

    func wait(_ load: () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            load()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        finish(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        finish(with: error)
    }

    // MARK: - Private Properties

    private var continuation: CheckedContinuation<Void, any Error>?

    // MARK: - Private Methods

    private func finish(with error: (any Error)?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }

}

enum TestHTML {

    // MARK: - Public Methods

    static func page(head: String = "", body: String = "") -> String {
        """
        <!doctype html>
        <html>
        <head><script>\(head)</script></head>
        <body>\(body)</body>
        </html>
        """
    }

}
