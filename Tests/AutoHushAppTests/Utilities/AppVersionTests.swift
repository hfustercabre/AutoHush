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

    @Test("reads a release candidate's tag and shown form, and writes both")
    func releaseCandidates() throws {
        let rc = try #require(AppVersion("v1.2.7-rc.2"))
        #expect(rc.components == [1, 2, 7] && rc.releaseCandidate == 2 && rc.isReleaseCandidate)
        #expect(rc.description == "1.2.7 RC 2" && rc.tagName == "1.2.7-rc.2")
        #expect(AppVersion("1.2.7 RC 2") == rc)
        #expect(AppVersion("1.2.7")?.tagName == "1.2.7")
        #expect(AppVersion("1.2.7-rc.0") == nil && AppVersion("1.2.7-rc.x") == nil && AppVersion("1.2.7-beta.1") == nil)
    }

    @Test("a release candidate comes after the candidates numbered lower and the releases before, and before its release")
    func releaseCandidateOrder() throws {
        let v = { (s: String) throws -> AppVersion in try #require(AppVersion(s)) }
        #expect(try v("1.2.6") < v("1.2.7-rc.1"))
        #expect(try v("1.2.7-rc.1") < v("1.2.7-rc.2"))
        #expect(try v("1.2.7-rc.2") < v("1.2.7"))
        #expect(try v("1.2.7") < v("1.2.8-rc.1"))
        #expect(try v("1.2.7-rc.1") != v("1.2.7"))
    }

    @Test("a bundle's version: its short version, and its release candidate's number from its own key")
    func bundleVersion() {
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.2.7"]) == AppVersion("1.2.7"))
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.2.7", "AutoHushReleaseCandidate": 1]) == AppVersion("1.2.7-rc.1"))
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.2.7", "AutoHushReleaseCandidate": "2"]) == AppVersion("1.2.7-rc.2"))
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.2.7", "AutoHushReleaseCandidate": 0])?.isReleaseCandidate == false)
        #expect(AppVersion(info: [:]) == nil)
    }
}
