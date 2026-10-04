import AppKit

/// The standard About panel, with a line about AutoHush, the project link and
/// a way to support it.
@MainActor
enum AboutPanel {
    static func show(playerName: String) {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits(playerName: playerName)])
    }

    /// The text under the app's name: what AutoHush does, the project link,
    /// and "Would you like to support me?" with a link to buy me a coffee below.
    static func credits(playerName: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        func link(_ text: String, to url: URL) -> NSAttributedString {
            var attributes = body
            attributes[.link] = url
            return NSAttributedString(string: text, attributes: attributes)
        }
        let summary = String(
            localized: "Pauses your music while other apps play audio, and resumes it afterwards. Works with \(playerName).",
            comment: "About panel; %@ is the music player, e.g. Spotify"
        )
        let question = String(localized: "Would you like to support me?",
                              comment: "About panel and Settings → General, before the Buy me a coffee link")
        let support = String(localized: "Buy me a coffee",
                             comment: "Link to the developer's Buy Me a Coffee page (About panel, Settings → General)")

        let credits = NSMutableAttributedString(string: summary + "\n", attributes: body)
        credits.append(link("github.com/\(ProjectInfo.repository)", to: ProjectInfo.homepage))
        credits.append(NSAttributedString(string: "\n\n" + question + "\n", attributes: body))
        credits.append(link(support, to: ProjectInfo.supportPage))
        return credits
    }
}
