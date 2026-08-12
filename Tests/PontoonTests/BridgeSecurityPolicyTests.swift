import Testing
@testable import Pontoon

@Suite("BridgeSecurityPolicy")
struct BridgeSecurityPolicyTests {

    @Test
    func anyOriginAllowsMainFrameOnly() {
        let policy = BridgeSecurityPolicy.anyOrigin()
        #expect(policy.allows(isMainFrame: true, origin: "https://pontoon.test"))
        #expect(!policy.allows(isMainFrame: false, origin: "https://pontoon.test"))
    }

    @Test
    func subframesAllowedWhenOptedIn() {
        let policy = BridgeSecurityPolicy.anyOrigin(allowsSubframes: true)
        #expect(policy.allows(isMainFrame: false, origin: "https://pontoon.test"))
    }

    @Test
    func originAllowlistIsMatchedExactly() throws {
        let policy = try BridgeSecurityPolicy(allowedOrigins: ["https://app.example.com"])
        #expect(policy.allows(isMainFrame: true, origin: "https://app.example.com"))
        #expect(!policy.allows(isMainFrame: true, origin: "https://evil.example.com"))
        #expect(!policy.allows(isMainFrame: true, origin: "http://app.example.com"))
        #expect(!policy.allows(isMainFrame: true, origin: "https://app.example.com:8443"))
    }

    @Test
    func emptyAllowlistBlocksEveryOrigin() throws {
        let policy = try BridgeSecurityPolicy(allowedOrigins: [])
        #expect(!policy.allows(isMainFrame: true, origin: "https://pontoon.test"))
    }

    @Test
    func frameRuleAppliesBeforeOriginRule() throws {
        let policy = try BridgeSecurityPolicy(allowedOrigins: ["https://app.example.com"])
        #expect(!policy.allows(isMainFrame: false, origin: "https://app.example.com"))
    }

    @Test
    func opaqueOriginIsRefusedEvenByAnyOrigin() {
        #expect(!BridgeSecurityPolicy.anyOrigin().allows(isMainFrame: true, origin: nil))
    }

    @Test
    func allowlistIsNormalizedOnConstruction() throws {
        let policy = try BridgeSecurityPolicy(allowedOrigins: [
            "https://App.Example.com:443",
            "https://other.test/some/path",
            "file://"
        ])
        #expect(policy.allowedOrigins == ["https://app.example.com", "https://other.test", "file://"])
        #expect(policy.allows(isMainFrame: true, origin: "https://app.example.com"))
        #expect(policy.allows(isMainFrame: true, origin: "file://"))
    }

    @Test(arguments: ["", "not an origin", "https://", "/relative"])
    func rejectsMalformedOrigins(_ origin: String) {
        #expect(throws: BridgeSetupError.invalidOrigin(origin)) {
            try BridgeSecurityPolicy(allowedOrigins: [origin])
        }
    }

}

@Suite("Origin")
struct OriginTests {

    @Test
    func buildsFromComponents() {
        #expect(Origin.string(scheme: "https", host: "a.test", port: nil) == "https://a.test")
        #expect(Origin.string(scheme: "https", host: "a.test", port: 443) == "https://a.test")
        #expect(Origin.string(scheme: "https", host: "a.test", port: 8443) == "https://a.test:8443")
        #expect(Origin.string(scheme: "http", host: "a.test", port: 80) == "http://a.test")
        #expect(Origin.string(scheme: "HTTPS", host: "A.Test", port: nil) == "https://a.test")
    }

    @Test
    func fileURLsShareOneOrigin() {
        #expect(Origin.string(scheme: "file", host: nil, port: nil) == "file://")
        #expect(Origin.string(scheme: "file", host: "", port: nil) == "file://")
    }

    @Test
    func opaqueOriginsHaveNoString() {
        #expect(Origin.string(scheme: nil, host: nil, port: nil) == nil)
        #expect(Origin.string(scheme: "", host: "", port: nil) == nil)
        #expect(Origin.string(scheme: "https", host: nil, port: nil) == nil)
    }

}
