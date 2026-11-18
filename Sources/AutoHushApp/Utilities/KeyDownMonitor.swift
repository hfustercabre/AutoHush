import AppKit

/// Keys AutoHush takes before the focused control (the arrows moving its
/// highlight, as in the menu; ↓ on the menu bar item): a local monitor of
/// key-downs that hands each key to `handle` on the main actor and swallows
/// the ones it took: the windows', the menu bar item's and an update's
/// notes'.
enum KeyDownMonitor {
    /// What `handle` gets of a key: the event itself isn't Sendable.
    struct Key: Sendable {
        let keyCode: UInt16
        let flags: NSEvent.ModifierFlags
        let characters: String?
        let windowNumber: Int
        /// It came to one of AutoHush's windows (not, say, the menu bar item).
        let hasWindow: Bool
    }

    /// The monitor, for `NSEvent.removeMonitor`; `handle` says whether it
    /// took the key.
    @MainActor @discardableResult
    static func install(_ handle: @escaping @MainActor (Key) -> Bool) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = Key(keyCode: event.keyCode, flags: event.modifierFlags, characters: event.characters,
                          windowNumber: event.windowNumber, hasWindow: event.window != nil)
            let handled = MainActor.assumeIsolated { handle(key) }
            return handled ? nil : event
        }
    }
}
