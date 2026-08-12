public import WebKit

public enum BridgeInjection: Sendable {
    case atDocumentStart
    case immediately
    case immediatelyAndAtDocumentStart
}

public extension WKWebView {

    // MARK: - Public Methods

    @discardableResult
    func installBridge(
        namespace: String,
        securityPolicy: BridgeSecurityPolicy,
        injecting injection: BridgeInjection = .atDocumentStart,
        contentWorld: WKContentWorld = .page,
        @NativeFunctionsBuilder functions: () -> [any NativeFunction]
    ) throws(BridgeSetupError) -> Bridge {
        let controller = configuration.userContentController
        if let installed = BridgeRegistry.entry(
            in: controller,
            namespace: namespace,
            contentWorld: contentWorld
        ) {
            guard installed.webView === self else {
                throw .namespaceInUseByAnotherWebView(namespace)
            }
            installed.bridge?.detach()
        }
        let bridge = try Bridge.make(
            namespace: namespace,
            securityPolicy: securityPolicy,
            functions: functions(),
            evaluator: WebViewJSEvaluator(webView: self, contentWorld: contentWorld)
        )
        controller.removeScriptMessageHandler(forName: namespace, contentWorld: contentWorld)
        controller.addScriptMessageHandler(
            ScriptMessageHandlerProxy(bridge: bridge),
            contentWorld: contentWorld,
            name: namespace
        )
        bridge.didInstall(in: controller, contentWorld: contentWorld)
        BridgeRegistry.register(
            bridge,
            webView: self,
            in: controller,
            namespace: namespace,
            contentWorld: contentWorld
        )
        switch injection {
        case .atDocumentStart:
            addBridgeUserScript(bridge, contentWorld: contentWorld)
        case .immediately:
            evaluateJavaScript(bridge.injectionCode, in: nil, in: contentWorld)
        case .immediatelyAndAtDocumentStart:
            addBridgeUserScript(bridge, contentWorld: contentWorld)
            evaluateJavaScript(bridge.injectionCode, in: nil, in: contentWorld)
        }
        return bridge
    }

}

extension Bridge {

    // MARK: - Internal Methods

    static func make(
        namespace: String,
        securityPolicy: BridgeSecurityPolicy,
        functions: [any NativeFunction],
        evaluator: any JSEvaluator
    ) throws(BridgeSetupError) -> Bridge {
        guard JSIdentifier.isValid(namespace) else { throw .invalidNamespace(namespace) }
        guard !namespace.hasPrefix(JSIdentifier.reservedPrefix) else {
            throw .reservedNamespace(namespace)
        }
        var names: Set<String> = []
        for function in functions {
            let name = function.name
            guard JSIdentifier.isValid(name) else { throw .invalidFunctionName(name) }
            guard !name.hasPrefix(JSIdentifier.reservedPrefix) else { throw .reservedFunctionName(name) }
            guard names.insert(name).inserted else { throw .duplicateFunctionName(name) }
        }
        let token = makeToken()
        return .init(
            caller: JSCaller(evaluator: evaluator, namespace: namespace, token: token),
            namespace: namespace,
            securityPolicy: securityPolicy,
            injectionCode: JSCodeTemplate.makeInjection(
                namespace: namespace,
                token: token,
                functionNames: functions.map(\.name)
            ),
            functions: functions
        )
    }

    // MARK: - Private Methods

    private static func makeToken() -> String {
        (0..<4).map { _ in String(UInt32.random(in: .min ... .max), radix: 36) }.joined()
    }

}

fileprivate extension WKWebView {

    // MARK: - Private Methods

    func addBridgeUserScript(_ bridge: Bridge, contentWorld: WKContentWorld) {
        configuration.userContentController.addUserScript(.init(
            source: bridge.injectionCode,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: !bridge.securityPolicy.allowsSubframes,
            in: contentWorld
        ))
    }

}
