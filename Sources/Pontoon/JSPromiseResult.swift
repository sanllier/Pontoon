public enum JSPromiseResult<Resolved: Decodable, Rejected: Decodable> {

    case resolved(Resolved)
    case rejected(Rejected)

    // MARK: - Public Properties

    public var resolvedValue: Resolved? {
        switch self {
        case .resolved(let value): value
        case .rejected: nil
        }
    }

    public var rejectedValue: Rejected? {
        switch self {
        case .resolved: nil
        case .rejected(let value): value
        }
    }

    public var isResolved: Bool {
        resolvedValue != nil
    }

}

extension JSPromiseResult: Sendable where Resolved: Sendable, Rejected: Sendable {}

extension JSPromiseResult: Equatable where Resolved: Equatable, Rejected: Equatable {}
