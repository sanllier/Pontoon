public enum JSVoid: Codable, Sendable {
    case void

    public init(from decoder: Decoder) throws {
        self = .void
    }

    public func encode(to encoder: Encoder) throws {
        struct Empty: Encodable {}
        var container = encoder.singleValueContainer()
        try container.encode(Empty())
    }
}
