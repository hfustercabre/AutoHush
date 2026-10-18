import Foundation

/// Settings' highlight, as the menu's (the user, 2026-10-18: "Lets add the
/// same over and arrows navigation system to the Settings Window"), on two
/// sides: the sidebar's pages and the page's controls, one highlighted at a
/// time (`KeyHighlight` each). ↑ and ↓ move within the side the highlight is
/// on; in the sidebar, each page shows at once, as in System Settings. → or
/// Return goes from the sidebar into the page; ← goes back, unless the
/// highlight is on a slider or a choice, which ← and → change. Return or
/// Space presses the page's control. The pointer moves the highlight to its
/// side too. Tab leaves it to the keyboard's focus.
@MainActor
final class SettingsKeys {
    enum Side { case sidebar, page }
    enum Key { case up, down, left, right, press, tab }

    let sidebar = KeyHighlight()
    let page = KeyHighlight()
    /// The side the highlight is on, or goes to first: the page.
    private(set) var side: Side = .page

    init() {
        sidebar.onHighlight = { [unowned self] in
            side = .sidebar
            page.clear()
        }
        page.onHighlight = { [unowned self] in
            side = .page
            sidebar.clear()
        }
    }

    /// Nothing highlighted, as the window opens.
    func clear() {
        sidebar.clear()
        page.clear()
        side = .page
    }

    /// Handles `key`; `false` leaves it to the window (a control with the
    /// keyboard's focus, `controlHasFocus`, takes ← → Return and Space while
    /// nothing is highlighted).
    @discardableResult func handle(_ key: Key, controlHasFocus: Bool = false) -> Bool {
        switch key {
        case .tab:
            sidebar.clear()
            page.clear()
            return false
        case .up, .down:
            let step = key == .down ? 1 : -1
            if side == .sidebar {
                sidebar.move(step)
                sidebar.press() // its page shows at once
            } else {
                page.move(step)
            }
            return true
        case .right, .press:
            if side == .sidebar, sidebar.highlighted != nil {
                page.move(1) // into the page: its first control
                return true
            }
            if key == .press { return page.press() }
            // On a control ← and → don't change, they do nothing.
            return page.adjust(1) || page.highlighted != nil
        case .left:
            if side == .sidebar { return sidebar.highlighted != nil }
            if page.adjust(-1) { return true }
            if page.highlighted == nil, controlHasFocus { return false }
            sidebar.highlightCurrent() // back to the sidebar, on the page shown
            return true
        }
    }
}
