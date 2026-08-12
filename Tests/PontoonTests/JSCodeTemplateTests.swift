import Testing
@testable import Pontoon

@Suite("JSCodeTemplate")
struct JSCodeTemplateTests {

    @Test
    func injectionLeavesNoPlaceholders() {
        let code = JSCodeTemplate.makeInjection(
            namespace: "myApp",
            token: "t0ken",
            functionNames: ["share", "getToken"]
        )
        #expect(!code.contains("$("))
        #expect(code.contains("myApp"))
        #expect(code.contains("t0ken"))
        #expect(code.contains("share"))
        #expect(code.contains("getToken"))
    }

}
