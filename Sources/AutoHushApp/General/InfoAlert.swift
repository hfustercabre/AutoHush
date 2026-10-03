import AppKit

/// A plain informational alert with an OK button, brought to the front.
@MainActor
enum InfoAlert {
    static func show(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
