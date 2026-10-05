import Foundation
import Testing
@testable import AutoHushApp

@Suite("ProjectInfo")
struct ProjectInfoTests {
    @Test("What's New opens the running version's release notes, or every release's when the version isn't known")
    func whatsNew() throws {
        let version = try #require(AppVersion("0.6.1"))
        #expect(ProjectInfo.whatsNewPage(for: version).absoluteString
            == "https://github.com/hfustercabre/AutoHush/releases/tag/v0.6.1")
        #expect(ProjectInfo.whatsNewPage(for: nil).absoluteString == "https://github.com/hfustercabre/AutoHush/releases")
    }

    @Test("Report an Issue opens a new issue on GitHub")
    func newIssue() {
        #expect(ProjectInfo.newIssuePage.absoluteString == "https://github.com/hfustercabre/AutoHush/issues/new")
    }
}
