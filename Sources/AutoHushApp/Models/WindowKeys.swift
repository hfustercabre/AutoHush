import AppKit

/// The keys of a window that guides the user (the welcome window's two
/// pages, Add a Web App, the learning window, Add an App and its check
/// warning; A4c, the user's pick, 2026-11-02), as Settings' with one side
/// (`SettingsKeys`): ↑ and ↓ move the highlight row by row, ← and → along a
/// row (tiles), Page Up and Page Down, Home and End jump, and the pointer
/// moves it too. Space presses the control it's on; Return is always the
/// window's main button's (Continue, Done, Start the Check: `MainButton`,
/// which SwiftUI gives it), as in macOS's windows with a default button,
/// and does nothing while it's dimmed (R2); in a window without one (the
/// logs window, `returnPresses`), it presses the lit control, as in
/// Settings. On a list that's one stop (the logs' entries), ↑ and ↓
/// scroll it until its end (`KeyHighlight.scroll`).
/// In a text field, what's typed stays there: ↓ or Tab leaves it for the controls,
/// from the first, Shift-Tab for the last, and ↑ stays the field's (the
/// search is the top). With a
/// search (the welcome's), a letter typed while a control is lit goes into
/// it (T1), as one into Add a Web App's address does (N5, 2026-11-06).
/// Tab and Shift-Tab go control by control, a row of several one after
/// the other (B, 2026-11-09), and into the search too, as macOS's key
/// loop goes into a field: Shift-Tab from the first control, Tab from the
/// last (K3, the user, 2026-11-10: "Into the field too"); they and the
/// arrows go on from a focused control (W9); a focused control
/// keeps its keys while nothing is lit, as in Settings, and a lit one,
/// whose tint hides the focus's, gets them (N6); Escape stays the
/// window's. Keys with nothing to act on do nothing, without a beep.
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
    /// The keyboard's focus lets go, once ↑, ↓, Tab or a jump moved the
    /// highlight (on from it: `KeyHighlight.focused`): one at a time, as in
    /// Settings (set by the window).
    var dropFocus: @MainActor () -> Void = {}
    /// The window's main buttons shown (`MainButton`), each with whether
    /// it can be pressed now.
    private var mainButtons: [UUID: Bool] = [:]
    /// Whether a main button can be pressed now: Return is its then.
    var mainButtonEnabled: Bool { mainButtons.values.contains(true) }
    /// The window's search takes the keyboard, its text kept, for a letter
    /// typed or Tab coming round to it; `false` when none shows. `nil`:
    /// typing isn't the keys' (set by the welcome window and Add a Web App).
    var focusSearch: (@MainActor () -> Bool)?
    /// Return presses the lit control, as in Settings: a window with no
    /// main button (the logs window, R6, 2026-11-10). Otherwise Return is
    /// the main button's.
    var returnPresses = false

    /// Handles `key` with `focus` on what has the keyboard; `false` leaves
    /// it to the window: Return while a main button can be pressed, a
    /// text field's keys but ↓, Tab and Shift-Tab, and Return, Space, ← and → while a control
    /// has the focus and nothing is lit.
    @discardableResult func handle(_ key: HighlightKey, focus: Focus = .none) -> Bool {
        switch focus {
        case .textField:
            guard [.down, .tab, .backTab].contains(key) else { return false }
            // Into the controls under it, from the first (Shift-Tab: the
            // last): what was lit before the typing may be gone.
            dropFocus()
            highlight.clear()
            switch key {
            case .tab: highlight.stepIn(1) // Tab's first, which right to left is the row's other end
            case .backTab: highlight.stepIn(-1)
            default: highlight.jump(.first)
            }
            return true
        case .control:
            if [.returnKey, .space, .left, .right].contains(key) {
                // The lit control shows the tint, the focus's hidden (K9):
                // it gets the keys, the focus let go (N6, 2026-11-06: Space
                // pressed the hidden one).
                guard highlight.highlighted != nil else { return false }
                dropFocus()
            }
        case .none:
            break
        }
        switch key {
        case .up, .down:
            // A list that's one stop scrolls, until its end (the logs' entries).
            if highlight.scroll(key == .down ? 1 : -1) { dropFocus(); return true }
            highlight.move(key == .down ? 1 : -1)
            dropFocus()
        case .tab, .backTab:
            tab(key == .tab ? 1 : -1)
        case .pageUp, .pageDown, .home, .end:
            dropFocus()
            if let jump = key.jump { highlight.jump(jump) }
        case .left, .right:
            let step = key == .right ? 1 : -1
            _ = highlight.adjust(step) || highlight.moveInRow(step)
        case .space:
            highlight.press()
        case .returnKey:
            if returnPresses { highlight.press() } else {
                // The main button's, as SwiftUI gives it; while it's dimmed, nothing.
                return !mainButtonEnabled
            }
        case .delete:
            return highlight.delete()
        }
        return true
    }

    /// Tab (1) or Shift-Tab (-1): the next control, or, past the last (the
    /// first), the search, the highlight let go (K3); without one, round.
    private func tab(_ step: Int) {
        if !highlight.step(step, wraps: false) {
            if let focusSearch, focusSearch() {
                highlight.clear()
                return
            }
            highlight.stepIn(step)
        }
        dropFocus()
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
