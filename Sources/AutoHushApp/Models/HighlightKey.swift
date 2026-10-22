import AppKit

/// The keys the menu's and Settings' highlight take (`KeyHighlight`), one
/// mapping for both so they never differ (the full check, 2026-10-18): the
/// plain arrows, Return (or Enter), Space, Delete (or Forward Delete), and
/// Tab, which hands over to the keyboard's focus with or without Shift. With ⌘, ⌥ or ⌃ (or ⇧, but for
/// Tab), a key is left to the window.
enum HighlightKey: Equatable {
    case up, down, left, right, returnKey, space, delete, tab

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let others: NSEvent.ModifierFlags = keyCode == 48 ? [.command, .option, .control] : [.command, .option, .control, .shift]
        guard modifiers.isDisjoint(with: others) else { return nil }
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 36, 76: self = .returnKey // Return, Enter
        case 49: self = .space
        case 51, 117: self = .delete // Delete, Forward Delete
        case 48: self = .tab
        default: return nil
        }
    }

    init?(_ event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }
}
