import Testing
@testable import Pontoon

@Suite("JSIdentifier")
struct JSIdentifierTests {

    @Test(arguments: ["a", "A", "_", "$", "_private", "$jquery", "myApp", "fn0", "a_b$c9"])
    func acceptsIdentifiers(_ identifier: String) {
        #expect(JSIdentifier.isValid(identifier))
    }

    @Test(arguments: [
        "",
        "0",
        "1abc",
        "a-b",
        "a b",
        "a.b",
        "a;alert(1)",
        "a'b",
        "a\"b",
        "a\nb",
        "имя",
        "функция",
        "a\\b",
        "window.myApp"
    ])
    func rejectsEverythingElse(_ identifier: String) {
        #expect(!JSIdentifier.isValid(identifier))
    }

    @Test
    func reservedPrefixIsItselfAValidIdentifier() {
        #expect(JSIdentifier.isValid(JSIdentifier.reservedPrefix))
    }

}
