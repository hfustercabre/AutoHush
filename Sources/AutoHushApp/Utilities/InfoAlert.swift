import AppKit

/// A plain informational alert, brought to the front. With no buttons
/// added, AppKit gives it its own OK button, in the app's language, which
/// Return presses.
@MainActor
enum InfoAlert {
    /// `run`: how the alert runs (`runInFront`); tests replace it.
    static func show(_ title: String, _ message: String,
                     run: @MainActor (NSAlert) -> NSApplication.ModalResponse = InfoAlert.runInFront) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        _ = run(alert)
    }

    /// Brings AutoHush to the front and runs `alert` until a button closes
    /// it, which it returns. Code that runs alerts takes it as a runner that
    /// tests replace, since a modal alert waits for a person.
    static func runInFront(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
