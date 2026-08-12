public import Foundation

public enum BridgeSetupError: Error, Equatable {
    case invalidNamespace(String)
    case reservedNamespace(String)
    case invalidFunctionName(String)
    case reservedFunctionName(String)
    case duplicateFunctionName(String)
    case invalidOrigin(String)
    case namespaceInUseByAnotherWebView(String)
}

extension BridgeSetupError: CustomStringConvertible, LocalizedError {

    // MARK: - Public Properties

    public var description: String {
        switch self {
        case .invalidNamespace(let namespace):
            "'\(namespace)' is not a valid JavaScript identifier and cannot be a namespace"
        case .reservedNamespace(let namespace):
            "'\(namespace)' uses the reserved '\(JSIdentifier.reservedPrefix)' prefix"
        case .invalidFunctionName(let name):
            "'\(name)' is not a valid JavaScript identifier and cannot be a function name"
        case .reservedFunctionName(let name):
            "'\(name)' uses the reserved '\(JSIdentifier.reservedPrefix)' prefix"
        case .duplicateFunctionName(let name):
            "Function '\(name)' is registered more than once"
        case .invalidOrigin(let origin):
            "'\(origin)' is not a valid origin: expected a scheme and a host, e.g. https://app.example.com"
        case .namespaceInUseByAnotherWebView(let namespace):
            "Namespace '\(namespace)' is already installed by another web view sharing this configuration"
        }
    }

    public var errorDescription: String? {
        description
    }

}
