import SwiftUI
import WebKit

struct ContentView: View {

    // MARK: - Public Properties

    var body: some View {
        VStack(spacing: 0) {
            WebViewContainer(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            controls
            logView
        }
        .background(Color(.systemGroupedBackground))
        .alert(
            model.alert?.title ?? "",
            isPresented: .init(
                get: { model.alert != nil },
                set: { if !$0 { model.alert = nil } }
            ),
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) { model.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Private Properties

    @StateObject private var model = DemoModel()

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swift → JavaScript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                button("Send message") { await model.sendMessageToPage() }
                button("Read state") { await model.readPageState() }
            }
            HStack(spacing: 8) {
                button("Rejecting call") { await model.callRejectingPageFunction() }
                button("Missing function") { await model.callMissingPageFunction() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Bridge log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.clearLog() }
                    .font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.log) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(color(for: entry.direction))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.direction == .failure ? Color.red : .primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 140)
        }
        .padding(16)
    }

    // MARK: - Private Methods

    private func button(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) {
            Task { await action() }
        }
        .font(.footnote.weight(.medium))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func color(for direction: LogEntry.Direction) -> Color {
        switch direction {
        case .toNative: .orange
        case .toPage: .blue
        case .failure: .red
        }
    }

}

struct WebViewContainer: UIViewRepresentable {

    // MARK: - Public Properties

    let model: DemoModel

    // MARK: - Public Methods

    func makeUIView(context: Context) -> WKWebView {
        model.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

}
