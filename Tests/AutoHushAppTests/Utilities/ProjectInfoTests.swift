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

    @Test("Report an Issue opens the bug report form on GitHub")
    func newIssue() {
        #expect(ProjectInfo.newIssuePage.absoluteString == "https://github.com/hfustercabre/AutoHush/issues/new?template=bug.yml")
    }

    @Test("Help opens the README's Tips and troubleshooting on GitHub")
    func help() {
        #expect(ProjectInfo.helpPage.absoluteString == "https://github.com/hfustercabre/AutoHush#tips-and-troubleshooting")
    }

    /// The README beside the sources, which a test kit run elsewhere (the
    /// old macOS VMs') may not have: skipped there, not failed.
    private static let readme = PackagePaths.root.appending(path: "README.md")

    @Test("Help's anchor is a heading the README has",
          .enabled(if: FileManager.default.fileExists(atPath: readme.path), "no README.md beside the sources"))
    func helpHeading() throws {
        let readme = try String(contentsOf: Self.readme, encoding: .utf8)
        let anchors = readme.split(separator: "\n").filter { $0.hasPrefix("#") }.map { Self.anchor(ofHeading: String($0)) }
        #expect(anchors.contains(ProjectInfo.helpAnchor))
    }

    /// The anchor GitHub gives a Markdown heading: its text in lowercase,
    /// without punctuation, spaces made hyphens.
    private static func anchor(ofHeading line: String) -> String {
        let text = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
        return String(text.compactMap { $0 == " " ? "-" : ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : nil) })
    }
}
