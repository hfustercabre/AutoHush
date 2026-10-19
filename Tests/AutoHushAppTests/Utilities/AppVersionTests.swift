import Testing
@testable import AutoHushApp

@Suite("AppVersion")
struct AppVersionTests {
    @Test("parses versions with or without a leading v")
    func parsing() {
        #expect(AppVersion("0.3.0")?.components == [0, 3, 0])
        #expect(AppVersion("v1.2")?.components == [1, 2])
        #expect(AppVersion("V10.0.1")?.description == "10.0.1")
        #expect(AppVersion("1.x") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test("compares versions numerically, padding missing parts")
    func comparison() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("0.10.0") > v("0.9.9"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try v("1.0.1") > v("1.0"))
        #expect(try v("0.2.0") < v("0.3.0"))
    }
}
