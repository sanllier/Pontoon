enum JSIdentifier {

    // MARK: - Public Properties

    static let reservedPrefix = "_pontoon"

    // MARK: - Public Methods

    static func isValid(_ identifier: String) -> Bool {
        guard let first = identifier.unicodeScalars.first, isValidHead(first) else { return false }
        return identifier.unicodeScalars.dropFirst().allSatisfy(isValidTail)
    }

}

fileprivate extension JSIdentifier {

    // MARK: - Private Methods

    static func isValidHead(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "a"..."z", "A"..."Z", "_", "$": true
        default: false
        }
    }

    static func isValidTail(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "0"..."9": true
        default: isValidHead(scalar)
        }
    }

}
