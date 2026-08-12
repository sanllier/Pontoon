public import Foundation

@MainActor
public protocol NativeFunction {
    var name: String { get }
    func invoke(
        parametersData: Data,
        bridge: Bridge
    ) async throws(BridgeError) -> NativeFunctionResult
}

public enum NativeFunctionResult: Sendable {

    case success(Encodable & Sendable)
    case failure(Encodable & Sendable)

    // MARK: - Public Properties

    public static var empty: NativeFunctionResult {
        .success(JSVoid.void)
    }

    // MARK: - Internal Properties

    var observedOutcome: BridgeEvent.Outcome {
        switch self {
        case .success: .resolved
        case .failure: .rejected
        }
    }

}

@MainActor
public protocol TypedNativeFunction: NativeFunction {
    associatedtype Parameters: Decodable
    func handle(parameters: Parameters, bridge: Bridge) async -> NativeFunctionResult
}

public extension TypedNativeFunction {

    // MARK: - Public Methods

    func invoke(
        parametersData: Data,
        bridge: Bridge
    ) async throws(BridgeError) -> NativeFunctionResult {
        let parameters: Parameters
        do { parameters = try JSONDecoder().decode(Parameters.self, from: parametersData) }
        catch { throw .nativeFunctionInvalidArguments(function: name, underlying: error) }
        return await handle(parameters: parameters, bridge: bridge)
    }

}

public struct ClosureNativeFunction<Parameters: Decodable>: TypedNativeFunction {

    // MARK: - Public Properties

    public let name: String

    // MARK: - Constructors

    public init(
        _ name: String,
        handler: @escaping @MainActor (Parameters, Bridge) async -> NativeFunctionResult
    ) {
        self.name = name
        self.handler = handler
    }

    // MARK: - Public Methods

    public func handle(parameters: Parameters, bridge: Bridge) async -> NativeFunctionResult {
        await handler(parameters, bridge)
    }

    // MARK: - Private Properties

    private let handler: @MainActor (Parameters, Bridge) async -> NativeFunctionResult

}

public extension ClosureNativeFunction where Parameters == JSVoid {

    // MARK: - Constructors

    init(
        _ name: String,
        handler: @escaping @MainActor (Bridge) async -> NativeFunctionResult
    ) {
        self.init(name, handler: { _, bridge in await handler(bridge) })
    }

}
