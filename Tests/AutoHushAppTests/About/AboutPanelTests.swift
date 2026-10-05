import AppKit
import Testing
@testable import AutoHushApp

@Suite("AboutPanel")
@MainActor
struct AboutPanelTests {
    @Test("the credits say what AutoHush does, and link to the project and to buy me a coffee")
    func credits() {
        let credits = AboutPanel.credits(playerNames: ["Jukebox"])

        #expect(credits.string == """
            Pauses your music while other apps play audio, and resumes it afterwards. Works with Jukebox.
            github.com/hfustercabre/AutoHush

            Would you like to support me?
            Buy me a coffee
            """)
        #expect(links(in: credits) == [
            "github.com/hfustercabre/AutoHush": ProjectInfo.homepage,
            "Buy me a coffee": ProjectInfo.supportPage,
        ])
    }

    @Test("the credits name every music player AutoHush works with")
    func everyPlayer() {
        let credits = AboutPanel.credits(playerNames: ["Jukebox", "Radio"])
        #expect(credits.string.hasPrefix(
            "Pauses your music while other apps play audio, and resumes it afterwards. Works with Jukebox and Radio."
        ))
    }

    /// Each linked piece of text and where it leads.
    private func links(in text: NSAttributedString) -> [String: URL] {
        var links: [String: URL] = [:]
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let url = value as? URL { links[text.attributedSubstring(from: range).string] = url }
        }
        return links
    }
}
