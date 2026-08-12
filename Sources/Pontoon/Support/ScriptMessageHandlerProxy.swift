import WebKit

@MainActor
final class ScriptMessageHandlerProxy: NSObject, WKScriptMessageHandlerWithReply {

    // MARK: - Constructors

    init(bridge: Bridge) {
        self.bridge = bridge
        super.init()
    }

    // MARK: - Public Methods

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        let request = Bridge.Request(message: message)
        Task { @MainActor in
            do throws(BridgeError) {
                switch try await bridge.route(request) {
                case .resolve(let payload): replyHandler(payload, nil)
                case .reject(let payload): replyHandler(nil, payload)
                }
            } catch {
                replyHandler(nil, Bridge.encodeBridgeError(error))
            }
        }
    }

    // MARK: - Private Properties

    private let bridge: Bridge

}
