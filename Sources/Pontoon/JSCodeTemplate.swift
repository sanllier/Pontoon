enum JSCodeTemplate {

    // MARK: - Public Methods

    static func makeInjection(
        namespace: String,
        token: String,
        functionNames: [String]
    ) -> String {
        var code = """
        (function() {
            const handlers = window.webkit && window.webkit.messageHandlers;
            const handler = handlers && handlers['$(API_NAMESPACE)'];
            if (!handler) { return; }
            const post = handler.postMessage.bind(handler);

            function refine(value) {
                return (value !== null && value !== undefined) ? value : {};
            }

            function define(target, name, value, enumerable) {
                try {
                    Object.defineProperty(target, name, {
                        value: value,
                        writable: false,
                        configurable: false,
                        enumerable: enumerable
                    });
                    return true;
                } catch (error) {
                    return false;
                }
            }

            function makeFailure(error) {
                let envelope = null;
                try { envelope = JSON.parse(error.message); } catch (parseError) { return error; }
                if (!envelope || typeof envelope !== 'object') { return error; }
                if (envelope.type === 'rejection') { return envelope.payload; }
                const failure = new Error(envelope.message || envelope.code || 'Pontoon bridge error');
                failure.name = 'PontoonBridgeError';
                failure.code = envelope.code;
                return failure;
            }

            function makeFunction(name) {
                return function(parameters) {
                    return post({ function: name, parameters: refine(parameters) })
                        .catch(function (error) { throw makeFailure(error); });
                };
            }

            const api = {};
            if (!define(window, '$(API_NAMESPACE)', api, true)) { return; }
            define(api, '$(TOKEN_KEY)', '$(TOKEN)', false);

            $(API_FUNCTIONS)
        })();
        """
        code.replace("$(API_NAMESPACE)", with: namespace)
        code.replace("$(TOKEN_KEY)", with: tokenKey)
        code.replace("$(TOKEN)", with: token)
        code.replace(
            "$(API_FUNCTIONS)",
            with: functionNames
                .map { "define(api, '\($0)', makeFunction('\($0)'), true);" }
                .joined(separator: "\n    ")
        )
        return code
    }

    static var call: String {
        """
        const target = window[namespace];
        if (!target || typeof target !== 'object') { return { kind: 'bridgeMissing' }; }
        if (target['\(tokenKey)'] !== token) { return { kind: 'bridgeMissing' }; }
        if (!Object.prototype.hasOwnProperty.call(target, name) || typeof target[name] !== 'function') {
            return { kind: 'functionNotFound' };
        }
        function refine(value) {
            return (value !== null && value !== undefined) ? value : {};
        }
        try {
            return { kind: 'resolved', payload: refine(await target[name](parameters)) };
        } catch (error) {
            if (error instanceof Error) {
                return {
                    kind: 'rejected',
                    payload: { name: error.name, message: error.message, stack: error.stack }
                };
            }
            return { kind: 'rejected', payload: refine(error) };
        }
        """
    }

    // MARK: - Internal Properties

    static let tokenKey = "_pontoonToken"

}
