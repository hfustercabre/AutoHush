import AppKit

/// While the update prompt shows an update's notes in their box: ↑ and ↓,
/// Page Up and Page Down, Home and End scroll them (`ScrollKeys`), as
/// nothing else in the prompt takes those keys; Return, Escape, Tab and
/// Space stay the prompt's (R5, the user, 2026-11-10: reach every control;
/// the box isn't selectable, which would scroll it to the middle as the
/// prompt opens, so it never has the keyboard itself).
@MainActor
final class ReleaseNotesKeys {
    private var monitor: Any?

    /// Watches the keys for `notes` until `stop()`.
    init(_ notes: NSScrollView) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak notes] event in
            let keyCode = event.keyCode, flags = event.modifierFlags, windowNumber = event.windowNumber
            let handled = MainActor.assumeIsolated {
                notes.map { Self.handle(keyCode, flags: flags, windowNumber: windowNumber, in: $0) } ?? false
            }
            return handled ? nil : event
        }
    }

    /// The prompt is answered: the keys are its own again.
    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// A key in the window `notes` are in scrolls them; `false` leaves it
    /// to the window: another key, another window's, or ↑ or ↓ at that end.
    static func handle(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int, in notes: NSScrollView) -> Bool {
        guard let window = notes.window, windowNumber == window.windowNumber,
              let key = HighlightKey(keyCode: keyCode, modifiers: flags) else { return false }
        return ScrollKeys.scroll(notes, key)
    }
}
