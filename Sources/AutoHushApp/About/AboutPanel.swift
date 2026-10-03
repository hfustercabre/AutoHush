import AppKit
import AutoHushKit

/// The standard About panel, with a line about AutoHush and the project link.
@MainActor
enum AboutPanel {
    static func show(playerName: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: "Pauses your music while other apps play audio, and resumes it afterwards. Works with \(playerName).\n",
            attributes: body
        )
        var link = body
        link[.link] = ProjectInfo.homepage
        credits.append(NSAttributedString(string: "github.com/\(ProjectInfo.repository)", attributes: link))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
