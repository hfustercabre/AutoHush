import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
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
