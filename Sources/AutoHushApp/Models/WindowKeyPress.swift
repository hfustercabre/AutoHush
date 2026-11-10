import AppKit

/// A key that a window with a highlight takes before its focused control
/// (Settings', `SettingsKeys`; a guiding window's, `WindowKeys`), read by
/// the rules they share; what each window does with it stays its own.
@MainActor
struct WindowKeyPress {
    /// The key as the highlight takes it (`HighlightKey`, the menu's
    /// mapping), if it's one.
    let key: HighlightKey?
    /// What has the keyboard in the window.
    let focus: WindowKeys.Focus
    /// Escape, without ⌘, ⌥, ⌃ or ⇧.
    let isEscape: Bool

    /// Escape's key code; the highlight doesn't take it (`HighlightKey`).
    private static let escapeKeyCode: UInt16 = 53

    /// `nil` when the window leaves the key alone: another window's, one
    /// while a sheet is attached, or one while an input method composes in
    /// a field (Japanese, Chinese…), where every key is its own: ↓ picks a
    /// candidate, Escape cancels it (the review of N4, 2026-11-06; the
    /// menu's search has the same rule). `fullKeyboardAccess`: macOS's
    /// keyboard navigation setting, with which a click may have given a
    /// control the focus.
    init?(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, windowNumber: Int, in window: NSWindow,
          fullKeyboardAccess: () -> Bool) {
        guard windowNumber == window.windowNumber, window.attachedSheet == nil else { return nil }
        if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() { return nil }
        let key = HighlightKey(keyCode: keyCode, modifiers: flags)
        self.key = key
        focus = window.firstResponder is NSText ? .textField // a field's editor
            : fullKeyboardAccess() && !(window.firstResponder is NSWindow) ? .control : .none
        isEscape = keyCode == Self.escapeKeyCode && flags.isDisjoint(with: [.command, .option, .control, .shift])
    }
}
