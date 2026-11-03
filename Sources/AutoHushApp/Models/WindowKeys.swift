import AppKit

/// The keys of a window that guides the user (the welcome window's two
/// pages, Add a Web App, the learning window, Add an App and its check
/// warning; A4c, the user's pick, 2026-11-02), as Settings' with one side
/// (`SettingsKeys`): ↑ and ↓ move the highlight row by row, ← and → along a
/// row (tiles), Page Up and Page Down, Home and End jump, and the pointer
/// moves it too. Space presses the control it's on; Return is always the
/// window's main button's (Continue, Done, Start the Check: `MainButton`,
/// which SwiftUI gives it), as in macOS's windows with a default button,
/// and does nothing while it's dimmed (R2).
/// In a text field, what's typed stays there: ↓ leaves it for the controls,
/// from the first, and ↑ stays the field's (the search is the top). With a
/// search (the welcome's), a letter typed while a control is lit goes into
/// it (T1). Tab and Shift-Tab move as ↓ and ↑ (`HighlightKey`); a focused
/// control keeps its keys as in Settings; Escape stays the window's. Keys with nothing to act on do nothing,
/// without a beep.
@MainActor
final class WindowKeys {
    /// What has the keyboard in the window.
    enum Focus {
        /// Nothing: the window itself.
        case none
        /// A control a click put it on (with keyboard navigation on).
        case control
        /// A text field, typing.
        case textField
    }

    let highlight = KeyHighlight()
    /// The keyboard's focus lets go, before ↑, ↓ or a jump moves the
    /// highlight: one at a time, as in Settings (set by the window).
    var dropFocus: @MainActor () -> Void = {}
    /// The window's main buttons shown (`MainButton`), each with whether
    /// it can be pressed now.
    private var mainButtons: [UUID: Bool] = [:]
    /// The window's search takes the keyboard, its text kept, for a letter
    /// typed; `false` when none shows. `nil`: typing isn't the keys' (set by
    /// the welcome window).
    var focusSearch: (@MainActor () -> Bool)?

    /// Handles `key` with `focus` on what has the keyboard; `false` leaves
    /// it to the window: Return while a main button can be pressed, a
    /// text field's keys but ↓, and Return, Space, ← and → while a control
    /// has the focus.
    @discardableResult func handle(_ key: HighlightKey, focus: Focus = .none) -> Bool {
        switch focus {
        case .textField:
            guard key == .down else { return false }
            // Into the controls under it, from the first: what was lit
            // before the typing may be gone.
            dropFocus()
            highlight.clear()
            highlight.move(1)
            return true
        case .control:
            if [.returnKey, .space, .left, .right].contains(key) { return false }
        case .none:
            break
        }
        switch key {
        case .up, .down:
            dropFocus()
            highlight.move(key == .down ? 1 : -1)
        case .pageUp, .pageDown, .home, .end:
            dropFocus()
            if let jump = key.jump { highlight.jump(jump) }
        case .left, .right:
            let step = key == .right ? 1 : -1
            _ = highlight.adjust(step) || highlight.moveInRow(step)
        case .space:
            highlight.press()
        case .returnKey:
            // The main button's, as SwiftUI gives it; while it's dimmed, nothing.
            return !mainButtons.values.contains(true)
        case .delete:
            return highlight.delete()
        }
        return true
    }

    /// A main button shown, or changed: `isEnabled`, or `nil` once it's gone.
    func mainButton(_ id: UUID, isEnabled: Bool?) {
        mainButtons[id] = isEnabled
    }

    /// A letter typed with `focus`: while a control is lit, the search takes
    /// the keyboard and the highlight goes. The letter itself
    /// goes on to the window, so into the search.
    func typed(focus: Focus = .none) {
        guard focus != .textField, highlight.highlighted != nil, let focusSearch, focusSearch() else { return }
        highlight.clear()
    }

    /// Whether a key typed `characters` with `modifiers`: something a text
    /// field would show (not Escape, an arrow or a function key), without
    /// ⌘, ⌥ or ⌃.
    static func isTyped(_ characters: String?, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.isDisjoint(with: [.command, .option, .control]), let characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value) // AppKit's function keys
        }
    }
}
