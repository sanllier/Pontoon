import Pontoon
import SwiftUI
import WebKit

struct DeviceInfo: Encodable, Sendable {
    var name: String
    var system: String
    var scale: Double
}

struct AlertParameters: Decodable {
    var title: String
    var message: String
}

struct NoteParameters: Decodable {
    var text: String
}

struct NotesCount: Encodable, Sendable {
    var count: Int
}

struct PurchaseParameters: Decodable {
    var productId: String
    var price: Double
}

struct PurchaseFailure: Encodable, Sendable {
    var reason: String
    var productId: String
}

struct NativeMessage: Encodable {
    var text: String
    var sentAt: String
}

struct PageState: Decodable {
    var clicks: Int
    var draft: String
}

struct PageRejection: Decodable {
    var name: String
    var message: String
}

struct LogEntry: Identifiable {
    let id = UUID()
    var direction: Direction
    var text: String

    enum Direction {
        case toNative
        case toPage
        case failure
    }
}

@MainActor
final class DemoModel: ObservableObject {

    // MARK: - Public Properties

    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var notes: [String] = []
    @Published var alert: AlertParameters?

    // MARK: - Public Methods

    func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: .init())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        do {
            let bridge = try webView.installBridge(
                namespace: "pontoon",
                securityPolicy: try .init(allowedOrigins: ["file://"])
            ) {
                ClosureNativeFunction("getDeviceInfo") { [weak self] _ in
                    self?.append(.toNative, "getDeviceInfo()")
                    return .success(DeviceInfo(
                        name: UIDevice.current.name,
                        system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
                        scale: Double(UIScreen.main.scale)
                    ))
                }
                ClosureNativeFunction("showAlert") { [weak self] (parameters: AlertParameters, _) in
                    self?.append(.toNative, "showAlert(\"\(parameters.title)\")")
                    self?.alert = parameters
                    return .empty
                }
                ClosureNativeFunction("saveNote") { [weak self] (parameters: NoteParameters, _) in
                    self?.append(.toNative, "saveNote(\"\(parameters.text)\")")
                    self?.notes.append(parameters.text)
                    return .success(NotesCount(count: self?.notes.count ?? 0))
                }
                ClosureNativeFunction("haptic") { [weak self] _ in
                    self?.append(.toNative, "haptic()")
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return .empty
                }
                ClosureNativeFunction("pageReady") { [weak self] _ in
                    self?.append(.toNative, "pageReady()")
                    Task { await self?.sendMessageToPage() }
                    return .empty
                }
                ClosureNativeFunction("purchase") { [weak self] (parameters: PurchaseParameters, _) in
                    self?.append(.failure, "purchase(\(parameters.productId)) rejected")
                    return .failure(PurchaseFailure(
                        reason: "Payments are disabled in the demo",
                        productId: parameters.productId
                    ))
                }
            }
            bridge.observer = self
            self.bridge = bridge
        } catch {
            append(.failure, "install failed: \(error)")
        }
        if let page = Bundle.main.url(forResource: "demo", withExtension: "html") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return webView
    }

    func sendMessageToPage() async {
        guard let bridge else { return }
        let message = NativeMessage(text: "Hello from Swift", sentAt: Self.timestamp())
        do {
            try await bridge.call("onNativeMessage", parameters: message)
            append(.toPage, "onNativeMessage(\"\(message.text)\")")
        } catch {
            append(.failure, "onNativeMessage: \(error)")
        }
    }

    func readPageState() async {
        guard let bridge else { return }
        do {
            let state = try await bridge.call("getPageState", as: PageState.self)
            append(.toPage, "getPageState() → clicks: \(state.clicks), draft: \"\(state.draft)\"")
        } catch {
            append(.failure, "getPageState: \(error)")
        }
    }

    func callRejectingPageFunction() async {
        guard let bridge else { return }
        let result: JSPromiseResult<JSVoid, PageRejection>
        do {
            result = try await bridge.call(
                "alwaysFails",
                as: JSVoid.self,
                rejectingAs: PageRejection.self
            )
        } catch {
            append(.failure, "alwaysFails: \(error)")
            return
        }
        switch result {
        case .resolved:
            append(.toPage, "alwaysFails() resolved unexpectedly")
        case .rejected(let rejection):
            append(.failure, "alwaysFails() rejected: \(rejection.name) — \(rejection.message)")
        }
    }

    func callMissingPageFunction() async {
        guard let bridge else { return }
        do {
            try await bridge.call("noSuchFunction")
        } catch {
            append(.failure, "noSuchFunction: \(error)")
        }
    }

    func clearLog() {
        log.removeAll()
    }

    // MARK: - Private Properties

    private var bridge: Bridge?

    // MARK: - Private Methods

    private func append(_ direction: LogEntry.Direction, _ text: String) {
        log.insert(LogEntry(direction: direction, text: text), at: 0)
        log = Array(log.prefix(40))
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

}

extension DemoModel: BridgeObserver {

    // MARK: - Public Methods

    func bridge(_ bridge: Bridge, didReceive event: BridgeEvent) {
        switch event {
        case .nativeCallFinished(_, let function, let outcome, let duration):
            append(.toNative, "← \(function) \(outcome) in \(Self.milliseconds(duration))")
        case .nativeCallFailed(_, let function, let error):
            append(.failure, "← \(function ?? "bridge") refused: \(error)")
        case .jsCallFinished(_, let function, let outcome, let duration):
            append(.toPage, "→ \(function) \(outcome) in \(Self.milliseconds(duration))")
        case .jsCallFailed(_, let function, let error):
            append(.failure, "→ \(function) failed: \(error)")
        case .nativeCallStarted, .jsCallStarted:
            break
        }
    }

    // MARK: - Private Methods

    private static func milliseconds(_ duration: Duration) -> String {
        let milliseconds = Double(duration.components.attoseconds) / 1e15
            + Double(duration.components.seconds) * 1000
        return String(format: "%.1f ms", milliseconds)
    }

}
