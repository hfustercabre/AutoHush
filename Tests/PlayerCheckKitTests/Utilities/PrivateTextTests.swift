import Foundation
import Testing
@testable import PlayerCheckKit

@Suite("PrivateText")
struct PrivateTextTests {
    @Test("the home folder is written ~, wherever a path holds it")
    func home() {
        let line = "playercheck /Users/someone/Applications/Player.app --logs /Users/someone/Library/Logs/AutoHush/Checks"
        #expect(PrivateText.redacted(line, home: "/Users/someone") == "playercheck ~/Applications/Player.app --logs ~/Library/Logs/AutoHush/Checks")
        #expect(PrivateText.redacted("/Applications/Player.app", home: "/Users/someone") == "/Applications/Player.app")
        #expect(PrivateText.redacted("/a/b", home: "/") == "/a/b")
    }

    @Test("a label shows its Play or Pause word only, never what it plays")
    func labels() {
        let words: Set<String> = ["play", "pause", "Reproducir"]
        #expect(PrivateText.label("Pause", words: words) == "“Pause”")
        #expect(PrivateText.label("reproducir", words: words) == "“reproducir”")
        #expect(PrivateText.label("Play Discover Weekly", words: words) == "“Play …”")
        #expect(PrivateText.label("Chill House", words: words) == "a name of 2 words")
        #expect(PrivateText.label("Mixes", words: words) == "a one-word name")
        #expect(PrivateText.label("  ", words: words) == "a button with no name")
    }

    @Test("a row is named by its place and what told it, never by its text")
    func rows() {
        #expect(PrivateText.row(1, of: 3, why: "its song found in its windows' titles") == "row 2 of 3, its song found in its windows' titles")
        #expect(PrivateText.row(0, of: 1, why: nil) == "row 1 of 1")
    }
}
