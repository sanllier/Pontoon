import WebKit

@MainActor
enum BridgeRegistry {

    // MARK: - Public Methods

    static func entry(
        in controller: WKUserContentController,
        namespace: String,
        contentWorld: WKContentWorld
    ) -> Entry? {
        prune()
        return entries[Key(controller: controller, namespace: namespace, contentWorld: contentWorld)]
    }

    static func register(
        _ bridge: Bridge,
        webView: WKWebView,
        in controller: WKUserContentController,
        namespace: String,
        contentWorld: WKContentWorld
    ) {
        prune()
        entries[Key(controller: controller, namespace: namespace, contentWorld: contentWorld)] = Entry(
            bridge: bridge,
            webView: webView
        )
    }

    static func unregister(
        in controller: WKUserContentController,
        namespace: String,
        contentWorld: WKContentWorld
    ) {
        entries.removeValue(forKey: Key(controller: controller, namespace: namespace, contentWorld: contentWorld))
        prune()
    }

    // MARK: - Internal Nested

    struct Entry {
        weak var bridge: Bridge?
        weak var webView: WKWebView?
    }

    // MARK: - Private Nested

    private struct Key: Hashable {
        let controller: ObjectIdentifier
        let namespace: String
        let contentWorld: ObjectIdentifier

        init(controller: WKUserContentController, namespace: String, contentWorld: WKContentWorld) {
            self.controller = ObjectIdentifier(controller)
            self.namespace = namespace
            self.contentWorld = ObjectIdentifier(contentWorld)
        }
    }

    // MARK: - Private Properties

    private static var entries: [Key: Entry] = [:]

    // MARK: - Private Methods

    private static func prune() {
        entries = entries.filter { $0.value.bridge != nil }
    }

}
