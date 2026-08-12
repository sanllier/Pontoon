import Foundation

public extension Bridge {

    // MARK: - Public Methods

    func call<Input: Encodable>(
        _ functionName: String,
        parameters: Input = JSVoid.void
    ) async throws(JSCallError) {
        try await callFunction(functionName, parameters: parameters) { outcome throws(JSCallError) in
            switch outcome {
            case .resolved: return
            case .rejected(let payload): throw .rejected(payloadJSON: Self.json(of: payload))
            }
        }
    }

    @discardableResult
    func call<Input: Encodable, Resolved: Decodable>(
        _ functionName: String,
        parameters: Input = JSVoid.void,
        as resolvedType: Resolved.Type
    ) async throws(JSCallError) -> Resolved {
        try await callFunction(functionName, parameters: parameters) { outcome throws(JSCallError) in
            switch outcome {
            case .resolved(let payload): return try Self.decode(Resolved.self, from: payload)
            case .rejected(let payload): throw .rejected(payloadJSON: Self.json(of: payload))
            }
        }
    }

    @discardableResult
    func call<Input: Encodable, Resolved: Decodable, Rejected: Decodable>(
        _ functionName: String,
        parameters: Input = JSVoid.void,
        as resolvedType: Resolved.Type,
        rejectingAs rejectedType: Rejected.Type
    ) async throws(JSCallError) -> JSPromiseResult<Resolved, Rejected> {
        try await callFunction(functionName, parameters: parameters) { outcome throws(JSCallError) in
            switch outcome {
            case .resolved(let payload): .resolved(try Self.decode(Resolved.self, from: payload))
            case .rejected(let payload): .rejected(try Self.decode(Rejected.self, from: payload))
            }
        }
    }

}

extension Bridge {

    // MARK: - Internal Methods

    static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        from payload: Data
    ) throws(JSCallError) -> Payload {
        do { return try JSONDecoder().decode(type, from: payload) }
        catch { throw .decodingFailed(error) }
    }

    static func json(of payload: Data) -> String {
        String(data: payload, encoding: .utf8) ?? ""
    }

}
