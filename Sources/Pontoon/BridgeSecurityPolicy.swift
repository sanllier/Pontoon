import Foundation

public struct BridgeSecurityPolicy: Sendable, Equatable {

    // MARK: - Public Properties

    public let allowedOrigins: Set<String>?
    public let allowsSubframes: Bool

    // MARK: - Constructors

    public init(allowedOrigins: Set<String>, allowsSubframes: Bool = false) throws(BridgeSetupError) {
        var normalized: Set<String> = []
        for origin in allowedOrigins {
            guard let url = URL(string: origin), let normalizedOrigin = Origin.string(of: url) else {
                throw .invalidOrigin(origin)
            }
            normalized.insert(normalizedOrigin)
        }
        self.allowedOrigins = normalized
        self.allowsSubframes = allowsSubframes
    }

    // MARK: - Public Methods

    public static func anyOrigin(allowsSubframes: Bool = false) -> BridgeSecurityPolicy {
        .init(allowedOrigins: nil, allowsSubframes: allowsSubframes)
    }

    // MARK: - Private Constructors

    private init(allowedOrigins: Set<String>?, allowsSubframes: Bool) {
        self.allowedOrigins = allowedOrigins
        self.allowsSubframes = allowsSubframes
    }

}

extension BridgeSecurityPolicy {

    // MARK: - Internal Methods

    func allows(isMainFrame: Bool, origin: String?) -> Bool {
        guard allowsSubframes || isMainFrame else { return false }
        guard let origin else { return false }
        guard let allowedOrigins else { return true }
        return allowedOrigins.contains(origin)
    }

}
