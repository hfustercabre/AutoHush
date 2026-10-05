import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    private func checker(status: Int, body: String) -> UpdateChecker {
        UpdateChecker { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/hfustercabre/AutoHush/releases/latest")
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    private let release030 = #"{"tag_name": "v0.3.0", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0"}"#

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

    @Test("a newer release is available")
    func newerRelease() async throws {
        let result = try await checker(status: 200, body: release030).check(currentVersion: AppVersion("0.2.0")!)
        #expect(result == .available(AppRelease(
            version: AppVersion("0.3.0")!,
            pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0")!
        )))
    }

    @Test("a newer release's disk image is read with its checksum")
    func diskImage() async throws {
        let body = #"""
            {"tag_name": "v0.3.0", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0",
             "assets": [
               {"name": "notes.txt", "browser_download_url": "https://github.com/hfustercabre/AutoHush/releases/download/v0.3.0/notes.txt"},
               {"name": "AutoHush-0.3.0.dmg",
                "browser_download_url": "https://github.com/hfustercabre/AutoHush/releases/download/v0.3.0/AutoHush-0.3.0.dmg",
                "digest": "sha256:3734F1D82E143134AA8048BF634A23448438C0792889F75B97235409DF1B4D23"}]}
            """#
        let result = try await checker(status: 200, body: body).check(currentVersion: AppVersion("0.2.0")!)
        guard case .available(let release) = result else { Issue.record("no update: \(result)"); return }
        #expect(release.diskImage == AppRelease.DiskImage(
            url: URL(string: "https://github.com/hfustercabre/AutoHush/releases/download/v0.3.0/AutoHush-0.3.0.dmg")!,
            sha256: "3734f1d82e143134aa8048bf634a23448438c0792889f75b97235409df1b4d23"
        ))
    }

    @Test("a newer release's notes are read, and blank notes are none", arguments: [
        ("\"### Added\\n\\n- **Notifications**\\n\"", "### Added\n\n- **Notifications**"),
        (#"" \n ""#, nil), ("null", nil),
    ])
    func notes(json: String, notes: String?) async throws {
        let body = #"{"tag_name": "v0.3.0", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0", "body": \#(json)}"#
        let result = try await checker(status: 200, body: body).check(currentVersion: AppVersion("0.2.0")!)
        guard case .available(let release) = result else { Issue.record("no update: \(result)"); return }
        #expect(release.notes == notes)
    }

    @Test("a disk image from anywhere but this repository's release downloads is ignored", arguments: [
        "https://evil.example/hfustercabre/AutoHush/releases/download/v0.3.0/AutoHush-0.3.0.dmg",
        "http://github.com/hfustercabre/AutoHush/releases/download/v0.3.0/AutoHush-0.3.0.dmg",
        "https://github.com/someone/else/releases/download/v0.3.0/AutoHush-0.3.0.dmg",
        "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0",
        "https://github.com/hfustercabre/AutoHush/releases/download/../../../someone/else/AutoHush-0.3.0.dmg",
        "file:///tmp/AutoHush-0.3.0.dmg",
    ])
    func ignoresOtherDownloads(url: String) async throws {
        let body = #"""
            {"tag_name": "v0.3.0", "html_url": "https://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0",
             "assets": [{"name": "AutoHush-0.3.0.dmg", "browser_download_url": "\#(url)"}]}
            """#
        let result = try await checker(status: 200, body: body).check(currentVersion: AppVersion("0.2.0")!)
        guard case .available(let release) = result else { Issue.record("no update: \(result)"); return }
        #expect(release.diskImage == nil)
    }

    @Test("only well-formed SHA-256 digests are kept")
    func digests() {
        #expect(UpdateChecker.sha256(fromDigest: "sha256:" + String(repeating: "Ab", count: 32)) == String(repeating: "ab", count: 32))
        #expect(UpdateChecker.sha256(fromDigest: "sha512:" + String(repeating: "ab", count: 32)) == nil)
        #expect(UpdateChecker.sha256(fromDigest: "sha256:" + String(repeating: "zz", count: 32)) == nil)
        #expect(UpdateChecker.sha256(fromDigest: "sha256:abc") == nil)
        #expect(UpdateChecker.sha256(fromDigest: nil) == nil)
    }

    @Test("a release page anywhere but this repository's releases on github.com is refused", arguments: [
        "https://evil.example/hfustercabre/AutoHush/releases/tag/v0.3.0",
        "http://github.com/hfustercabre/AutoHush/releases/tag/v0.3.0",
        "https://github.com/someone/else/releases/tag/v0.3.0",
        "https://github.com/hfustercabre/AutoHush/releases/../../../someone/else",
        "file:///Applications/Calculator.app",
        "smb://server/share",
        "x-apple.systempreferences:com.apple.preference.security",
    ])
    func refusesOtherPages(page: String) async {
        let body = #"{"tag_name": "v0.3.0", "html_url": "\#(page)"}"#
        await #expect(throws: UpdateCheckError.unreadableRelease) {
            try await checker(status: 200, body: body).check(currentVersion: AppVersion("0.2.0")!)
        }
    }

    @Test("the same or an older release is up to date")
    func upToDate() async throws {
        let result = try await checker(status: 200, body: release030).check(currentVersion: AppVersion("0.3.0")!)
        #expect(result == .upToDate(latest: AppVersion("0.3.0")!))
    }

    @Test("no published release is reported as such")
    func noReleases() async throws {
        let result = try await checker(status: 404, body: #"{"message": "Not Found"}"#).check(currentVersion: AppVersion("0.2.0")!)
        #expect(result == .noReleases)
    }

    @Test("update traffic keeps no cache or cookies on disk")
    func privateSession() {
        let configuration = URLSession.updates.configuration
        #expect(configuration.urlCache?.diskCapacity ?? 0 == 0)
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)
    }

    @Test("other HTTP statuses and malformed releases are errors")
    func errors() async {
        await #expect(throws: UpdateCheckError.badResponse(500)) {
            try await checker(status: 500, body: "").check(currentVersion: AppVersion("0.2.0")!)
        }
        await #expect(throws: UpdateCheckError.unreadableRelease) {
            try await checker(status: 200, body: #"{"tag_name": "latest"}"#).check(currentVersion: AppVersion("0.2.0")!)
        }
    }
}
