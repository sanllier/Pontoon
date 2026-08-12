import Foundation
import WebKit

enum Origin {

    // MARK: - Public Methods

    static func string(scheme: String?, host: String?, port: Int?) -> String? {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty else { return nil }
        guard let host = host?.lowercased(), !host.isEmpty else {
            return scheme == "file" ? "file://" : nil
        }
        guard let port, port != defaultPort(for: scheme) else { return "\(scheme)://\(host)" }
        return "\(scheme)://\(host):\(port)"
    }

    static func string(of url: URL) -> String? {
        string(scheme: url.scheme, host: url.host, port: url.port)
    }

    // MARK: - Private Methods

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https", "wss": 443
        case "http", "ws": 80
        default: nil
        }
    }

}

extension WKSecurityOrigin {

    // MARK: - Public Properties

    var originString: String? {
        Origin.string(scheme: `protocol`, host: host, port: port == 0 ? nil : port)
    }

}
