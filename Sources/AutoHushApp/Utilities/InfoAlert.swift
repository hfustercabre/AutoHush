import AppKit

/// A plain informational alert, brought to the front. With no buttons
/// added, AppKit gives it its own OK button, in the app's language, which
/// Return presses.
@MainActor
enum InfoAlert {
    /// Runs `show`, which runs an alert, from the run loop once the work
    /// that asked for it is done, and no other alert or panel is open: run
    /// from a main-actor task, an alert's modal loop would hold up every
    /// other main-actor job until it closes; in the run loop's default mode
    /// only, it waits while another modal loop runs, so alerts never open
    /// over each other (the workflow audit, 2026-10-22).
    static func whenNoneOpen(_ show: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default]) { MainActor.assumeIsolated(show) }
    }

    /// `run`: how the alert runs (`runInFront`); tests replace it.
    /// `action`: a button that fixes what it says, first (Return presses
    /// it), with OK after it (Escape).
    static func show(_ title: String, _ message: String, action: (title: String, perform: () -> Void)? = nil,
                     run: @MainActor (NSAlert) -> NSApplication.ModalResponse = InfoAlert.runInFront) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        guard let action else {
            _ = run(alert)
            return
        }
        alert.addButton(withTitle: action.title)
        alert.addButton(withTitle: String(localized: "OK", comment: "Button that closes an alert")).keyEquivalent = "\u{1b}"
        if run(alert) == .alertFirstButtonReturn { action.perform() }
    }

    /// Brings AutoHush to the front and runs `alert` until a button closes
    /// it, which it returns. Code that runs alerts takes it as a runner that
    /// tests replace, since a modal alert waits for a person.
    static func runInFront(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.becomeActive()
        return alert.runModal()
    }
}
