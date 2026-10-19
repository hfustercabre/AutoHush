import AppKit
import SwiftUI

/// A push button that puts `text` on the clipboard, then says "Copied" for
/// 2 s, VoiceOver hearing it too (`CopiedFeedback`): Settings →
/// Diagnostics' Copy Report, the logs window's Copy Logs.
struct CopyButton: View {
    let title: Text
    /// What it copies; `nil`: nothing to copy now.
    let text: () -> String?
    @State private var copied = CopiedFeedback()

    var body: some View {
        Button(action: copy) {
            if copied.isShown { Text(verbatim: Self.copiedText) } else { title }
        }
        .buttonStyle(.chip)
    }

    private func copy() {
        guard let text = text() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied.show()
        AccessibilityNotification.Announcement(Self.copiedText).post()
    }

    /// Said on the button for a moment after a click.
    static var copiedText: String {
        String(localized: "Copied", comment: "Settings → Diagnostics after Copy Report, and the logs window's Copy Logs button, for a moment after a click")
    }
}
