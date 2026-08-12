public import Foundation

public enum BridgeError: Error {
    case brokenNativeFunctionRequest
    case requestFromDisallowedFrame(origin: String)
    case nativeFunctionNotDefined(function: String)
    case nativeFunctionInvalidArguments(function: String, underlying: any Error)
    case cannotSerializeResponse(function: String, underlying: any Error)
}

extension BridgeError: CustomStringConvertible, LocalizedError {

    // MARK: - Public Properties

    public var code: String {
        switch self {
        case .brokenNativeFunctionRequest: "brokenRequest"
        case .requestFromDisallowedFrame: "disallowedFrame"
        case .nativeFunctionNotDefined: "functionNotDefined"
        case .nativeFunctionInvalidArguments: "invalidArguments"
        case .cannotSerializeResponse: "cannotSerializeResponse"
        }
    }

    public var description: String {
        switch self {
        case .brokenNativeFunctionRequest:
            "Malformed native function request"
        case .requestFromDisallowedFrame(let origin):
            "Request from disallowed frame: \(origin)"
        case .nativeFunctionNotDefined(let function):
            "Native function '\(function)' is not defined"
        case .nativeFunctionInvalidArguments(let function, let underlying):
            "Invalid arguments for native function '\(function)': \(underlying)"
        case .cannotSerializeResponse(let function, let underlying):
            "Cannot serialize response of native function '\(function)': \(underlying)"
        }
    }

    public var errorDescription: String? {
        description
    }

    // MARK: - Internal Properties

    var pageMessage: String {
        switch self {
        case .brokenNativeFunctionRequest: "Malformed request"
        case .requestFromDisallowedFrame: "Frame is not allowed to use this bridge"
        case .nativeFunctionNotDefined: "Function is not defined"
        case .nativeFunctionInvalidArguments: "Invalid arguments"
        case .cannotSerializeResponse: "Response could not be serialized"
        }
    }

}
