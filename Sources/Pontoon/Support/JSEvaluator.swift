import WebKit

enum JSEvaluationError: Error {
    case evaluatorUnavailable
    case failed(any Error)
}

@MainActor
protocol JSEvaluator: AnyObject {
    var currentOrigin: String? { get }
    func evaluateAsyncFunction(
        body: String,
        arguments: [String: Any]
    ) async throws(JSEvaluationError) -> Any?
}

@MainActor
final class WebViewJSEvaluator: JSEvaluator {

    // MARK: - Public Properties

    var currentOrigin: String? {
        webView?.url.flatMap(Origin.string(of:))
    }

    // MARK: - Constructors

    init(webView: WKWebView, contentWorld: WKContentWorld) {
        self.webView = webView
        self.contentWorld = contentWorld
    }

    // MARK: - Public Methods

    func evaluateAsyncFunction(
        body: String,
        arguments: [String: Any]
    ) async throws(JSEvaluationError) -> Any? {
        guard let webView else { throw .evaluatorUnavailable }
        do {
            return try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                contentWorld: contentWorld
            )
        } catch {
            throw .failed(error)
        }
    }

    // MARK: - Internal Properties

    private(set) weak var webView: WKWebView?

    // MARK: - Private Properties

    private let contentWorld: WKContentWorld

}
