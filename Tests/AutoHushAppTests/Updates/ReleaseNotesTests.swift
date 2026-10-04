import AppKit
import Testing
@testable import AutoHushApp

@Suite("ReleaseNotes")
struct ReleaseNotesTests {
    /// A CHANGELOG section as GitHub returns it: wrapped list items, bold,
    /// code and a link.
    private let notes = """
        ### Added

        - **Notifications** tell you when an update is
          available, downloaded or installed.
        - Run `brew upgrade` or see [the page](https://example.com).

        ---

        A closing line
        that wraps.
        """

    @Test("headings, list items and paragraphs are told apart, and wrapped lines joined")
    func blocks() {
        #expect(ReleaseNotes.blocks(in: notes) == [
            .heading("Added"),
            .item("**Notifications** tell you when an update is available, downloaded or installed."),
            .item("Run `brew upgrade` or see [the page](https://example.com)."),
            .paragraph("A closing line that wraps."),
        ])
    }

    @Test("the text has bullets, bold kept, and links as plain text")
    func text() {
        let text = ReleaseNotes.text(from: notes)
        #expect(text.string == """
            Added
            •\tNotifications tell you when an update is available, downloaded or installed.
            •\tRun brew upgrade or see the page.
            A closing line that wraps.
            """)
        let bold = { (word: String) -> Bool in
            let range = (text.string as NSString).range(of: word)
            let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            return font?.fontDescriptor.symbolicTraits.contains(.bold) == true
        }
        #expect(bold("Added"))
        #expect(bold("Notifications"))
        #expect(!bold("tell you"))
        var hasLink = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { hasLink = true }
        }
        #expect(!hasLink)
    }

    @Test("very long notes are cut")
    func cut() {
        let text = ReleaseNotes.text(from: String(repeating: "Lots of news. ", count: 500))
        #expect(text.length == ReleaseNotes.maxLength + 1)
        #expect(text.string.hasSuffix("…"))
    }

    @Test("an emoji at the cut is left out whole, never halved")
    func cutBeforeEmoji() {
        // "🎵" is two UTF-16 units; this puts it across the limit.
        let text = ReleaseNotes.text(from: String(repeating: "a", count: ReleaseNotes.maxLength - 1) + "🎵 and more")
        #expect(text.length == ReleaseNotes.maxLength)
        #expect(text.string == String(repeating: "a", count: ReleaseNotes.maxLength - 1) + "…")
    }
}
