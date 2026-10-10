import AppKit

/// A plain informational alert, brought to the front. With no buttons
/// added, AppKit gives it its own OK button, in the app's language, which
/// Return presses.
@MainActor
enum InfoAlert {
    static func show(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApp.activate()
        alert.runModal()
    }
}
