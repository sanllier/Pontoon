@resultBuilder
public enum NativeFunctionsBuilder {

    // MARK: - Public Methods

    public static func buildExpression(_ expression: any NativeFunction) -> [any NativeFunction] {
        [expression]
    }

    public static func buildExpression(_ expression: [any NativeFunction]) -> [any NativeFunction] {
        expression
    }

    public static func buildBlock(_ components: [any NativeFunction]...) -> [any NativeFunction] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any NativeFunction]?) -> [any NativeFunction] {
        component ?? []
    }

    public static func buildEither(first component: [any NativeFunction]) -> [any NativeFunction] {
        component
    }

    public static func buildEither(second component: [any NativeFunction]) -> [any NativeFunction] {
        component
    }

    public static func buildArray(_ components: [[any NativeFunction]]) -> [any NativeFunction] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [any NativeFunction]) -> [any NativeFunction] {
        component
    }

}
