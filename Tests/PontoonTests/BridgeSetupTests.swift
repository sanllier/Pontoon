import Testing
@testable import Pontoon

@Suite("Bridge setup") @MainActor
struct BridgeSetupTests {

    @Test
    func buildsWithValidConfiguration() throws {
        let bridge = try Fixture.makeBridge(namespace: "myApp") {
            EchoFunction()
            RejectingFunction()
        }
        #expect(bridge.namespace == "myApp")
        #expect(bridge.injectionCode.contains("define(api, 'echo'"))
        #expect(bridge.injectionCode.contains("define(api, 'reject'"))
    }

    @Test(arguments: ["", "my-app", "my app", "0app", "window.myApp", "app;alert(1)"])
    func rejectsInvalidNamespace(_ namespace: String) {
        #expect(throws: BridgeSetupError.invalidNamespace(namespace)) {
            try Fixture.makeBridge(namespace: namespace) { EchoFunction() }
        }
    }

    @Test(arguments: ["", "get-token", "get token", "1st", "fn');alert('x"])
    func rejectsInvalidFunctionName(_ name: String) {
        #expect(throws: BridgeSetupError.invalidFunctionName(name)) {
            try Fixture.makeBridge { EchoFunction(name: name) }
        }
    }

    @Test(arguments: ["_pontoon", "_pontoonVersion", "_pontoonInternal"])
    func rejectsReservedFunctionName(_ name: String) {
        #expect(throws: BridgeSetupError.reservedFunctionName(name)) {
            try Fixture.makeBridge { EchoFunction(name: name) }
        }
    }

    @Test
    func rejectsDuplicateFunctionName() {
        #expect(throws: BridgeSetupError.duplicateFunctionName("echo")) {
            try Fixture.makeBridge {
                EchoFunction()
                EchoFunction()
            }
        }
    }

    @Test
    func resultBuilderAcceptsPreparedArrays() throws {
        let prepared: [any NativeFunction] = [EchoFunction(), RejectingFunction()]
        let bridge = try Fixture.makeBridge(namespace: "myApp") { prepared }
        #expect(bridge.injectionCode.contains("define(api, 'echo'"))
        #expect(bridge.injectionCode.contains("define(api, 'reject'"))
    }

    @Test
    func resultBuilderSupportsConditionals() throws {
        func makeCode(includeReject: Bool) throws -> String {
            try Fixture.makeBridge {
                EchoFunction()
                if includeReject {
                    RejectingFunction()
                }
            }.injectionCode
        }
        #expect(try makeCode(includeReject: true).contains("'reject'"))
        #expect(try !makeCode(includeReject: false).contains("'reject'"))
    }

}
