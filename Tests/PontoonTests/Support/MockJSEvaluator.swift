import Foundation
@testable import Pontoon

@MainActor
final class MockJSEvaluator: JSEvaluator {

    // MARK: - Public Properties

    var response: Result<Any?, JSEvaluationError> = .success(nil)
    var currentOrigin: String? = "https://pontoon.test"
    private(set) var invocations: [Invocation] = []

    var lastInvocation: Invocation? {
        invocations.last
    }

    // MARK: - Public Methods

    func respondResolved(_ payload: Any) {
        response = .success(["kind": "resolved", "payload": payload])
    }

    func respondRejected(_ payload: Any) {
        response = .success(["kind": "rejected", "payload": payload])
    }

    func respondFunctionNotFound() {
        response = .success(["kind": "functionNotFound"])
    }

    func evaluateAsyncFunction(
        body: String,
        arguments: [String: Any]
    ) async throws(JSEvaluationError) -> Any? {
        invocations.append(Invocation(body: body, arguments: arguments))
        switch response {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    // MARK: - Public Nested

    struct Invocation {
        var body: String
        var arguments: [String: Any]

        var namespace: String? { arguments["namespace"] as? String }
        var functionName: String? { arguments["name"] as? String }
        var parameters: Any? { arguments["parameters"] }
    }

}
