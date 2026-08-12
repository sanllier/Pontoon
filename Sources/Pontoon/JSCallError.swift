public import Foundation

public enum JSCallError: Error {
    case bridgeDetached
    case documentNotAllowed(origin: String?)
    case functionIsNative(String)
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case executionFailed(any Error)
    case invalidResponse
    case functionNotFound
    case bridgeMissingOnPage
    case rejected(payloadJSON: String)
}

enum EncodingFailure: Error {
    case invalidUTF8
}

extension JSCallError: CustomStringConvertible, LocalizedError {

    // MARK: - Public Properties

    public var description: String {
        switch self {
        case .bridgeDetached:
            "Bridge is not installed, or its web view is gone"
        case .documentNotAllowed(let origin):
            "Current document (\(origin ?? "opaque origin")) is not allowed by the security policy"
        case .functionIsNative(let name):
            "'\(name)' is a native function of this bridge, not a page function"
        case .encodingFailed(let underlying):
            "Parameters could not be encoded: \(underlying)"
        case .decodingFailed(let underlying):
            "Settled payload could not be decoded: \(underlying)"
        case .executionFailed(let underlying):
            "JavaScript evaluation failed: \(underlying)"
        case .invalidResponse:
            "Bridge script returned an unexpected response"
        case .functionNotFound:
            "No such function on the page"
        case .bridgeMissingOnPage:
            "Bridge script is not present in the current document"
        case .rejected(let payloadJSON):
            "Page rejected the call: \(payloadJSON)"
        }
    }

    public var errorDescription: String? {
        description
    }

}
