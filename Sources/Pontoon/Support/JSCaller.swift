import Foundation

enum JSCallOutcome {
    case resolved(payload: Data)
    case rejected(payload: Data)

    // MARK: - Public Properties

    var observedOutcome: BridgeEvent.Outcome {
        switch self {
        case .resolved: .resolved
        case .rejected: .rejected
        }
    }
}

@MainActor
struct JSCaller {

    // MARK: - Public Properties

    let evaluator: any JSEvaluator
    let namespace: String
    let token: String

    var currentOrigin: String? {
        evaluator.currentOrigin
    }

    // MARK: - Public Methods

    func call<Input: Encodable>(
        _ functionName: String,
        parameters: Input
    ) async throws(JSCallError) -> JSCallOutcome {
        let parametersValue: Any
        do {
            let data = try JSONEncoder().encode(parameters)
            guard let value = JSONValue.value(from: data) else { throw EncodingFailure.invalidUTF8 }
            parametersValue = value
        } catch {
            throw .encodingFailed(error)
        }

        let rawResponse: Any?
        do {
            rawResponse = try await evaluator.evaluateAsyncFunction(
                body: JSCodeTemplate.call,
                arguments: [
                    "namespace": namespace,
                    "name": functionName,
                    "parameters": parametersValue,
                    "token": token
                ]
            )
        } catch {
            switch error {
            case .evaluatorUnavailable: throw .bridgeDetached
            case .failed(let underlying): throw .executionFailed(underlying)
            }
        }

        guard let response = rawResponse as? [String: Any],
            let kind = response["kind"] as? String
        else {
            throw .invalidResponse
        }

        switch kind {
        case "functionNotFound": throw .functionNotFound
        case "bridgeMissing": throw .bridgeMissingOnPage
        case "resolved": return .resolved(payload: try Self.payload(of: response))
        case "rejected": return .rejected(payload: try Self.payload(of: response))
        default: throw .invalidResponse
        }
    }

    // MARK: - Private Methods

    private static func payload(of response: [String: Any]) throws(JSCallError) -> Data {
        guard let payload = response["payload"], let data = JSONValue.data(from: payload) else {
            throw .invalidResponse
        }
        return data
    }

}
