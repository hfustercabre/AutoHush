import AppKit

/// The keys the menu's and Settings' highlight take (`KeyHighlight`), one
/// mapping for both so they never differ (the full check, 2026-10-18): the
/// plain arrows, Page Up and Page Down, Home and End (fn with the arrows on
/// a laptop, 2026-11-01), Return (or Enter), Space, Delete (or Forward
/// Delete), and Tab and Shift-Tab, which go to the next and the previous
/// control, one by one (B, the user's pick, 2026-11-09; as ↓ and ↑ before,
/// 2026-11-03). With ⌘, ⌥ or ⌃ (or ⇧, but for Tab), a key is left to the
/// window.
enum HighlightKey: Equatable {
    case up, down, left, right, pageUp, pageDown, home, end, returnKey, space, delete, tab, backTab

    /// Tab's key code: `tab`, or `backTab` with Shift.
    private static let tabKeyCode: UInt16 = 48

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let others: NSEvent.ModifierFlags = keyCode == Self.tabKeyCode ? [.command, .option, .control] : [.command, .option, .control, .shift]
        guard modifiers.isDisjoint(with: others) else { return nil }
        switch keyCode {
        case 126: self = .up
        case 125: self = .down
        case 123: self = .left
        case 124: self = .right
        case 116: self = .pageUp
        case 121: self = .pageDown
        case 115: self = .home
        case 119: self = .end
        case 36, 76: self = .returnKey // Return, Enter
        case 49: self = .space
        case 51, 117: self = .delete // Delete, Forward Delete
        case Self.tabKeyCode: self = modifiers.contains(.shift) ? .backTab : .tab
        default: return nil
        }
    }

    init?(_ event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    /// Page Up or Down, Home or End: the highlight jumps (`KeyHighlight.jump`).
    var jump: KeyHighlight.Jump? {
        switch self {
        case .pageUp: .pageUp
        case .pageDown: .pageDown
        case .home: .first
        case .end: .last
        default: nil
        }
    }
}
