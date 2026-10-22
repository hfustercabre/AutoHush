import Foundation

/// Settings' highlight, as the menu's (the user, 2026-10-18: "Lets add the
/// same over and arrows navigation system to the Settings Window"), on two
/// sides: the sidebar's pages and the page's controls, one highlighted at a
/// time (`KeyHighlight` each). ↑ and ↓ move within the sidebar while it
/// holds the highlight, each page showing at once as in System Settings,
/// else through the page, row by row. → or Return goes from the sidebar
/// into the page; ← goes back, unless the highlight is on a slider or a
/// choice, which ← and → change, or in a row of several (tiles), which they
/// move along first. Return or Space presses the page's control. The
/// pointer moves the highlight to its side too. Tab leaves it to the
/// keyboard's focus, and a control that has the focus takes Return, Space,
/// ← and → itself, as in the menu (the full check, 2026-10-18). Delete
/// removes the highlighted control if it can be (an added app's tile).
/// Keys with nothing to act on do nothing, without a beep.
@MainActor
final class SettingsKeys {
    enum Side { case sidebar, page }

    let sidebar = KeyHighlight()
    let page = KeyHighlight()
    /// The side the highlight is on, or goes to first: the page.
    private(set) var side: Side = .page

    init() {
        sidebar.onHighlight = { [weak self] in
            self?.side = .sidebar
            self?.page.clear()
        }
        page.onHighlight = { [weak self] in
            self?.side = .page
            self?.sidebar.clear()
        }
    }

    /// Nothing highlighted, as the window opens.
    func clear() {
        sidebar.clear()
        page.clear()
        side = .page
    }

    /// Handles `key`; `false` leaves it to the window: Tab, and Return,
    /// Space, ← and → while a control has the keyboard's focus
    /// (`controlHasFocus`).
    @discardableResult func handle(_ key: HighlightKey, controlHasFocus: Bool = false) -> Bool {
        if controlHasFocus, [.returnKey, .space, .left, .right].contains(key) { return false }
        switch key {
        case .tab:
            clear()
            return false
        case .delete:
            return page.delete()
        case .up, .down:
            let step = key == .down ? 1 : -1
            if side == .sidebar, sidebar.highlighted != nil {
                sidebar.move(step)
                sidebar.press() // its page shows at once
            } else {
                // The sidebar let go of it (the pointer left, Tab): the page's.
                side = .page
                page.move(step)
            }
            return true
        case .returnKey, .space:
            if side == .sidebar, sidebar.highlighted != nil {
                page.move(1) // into the page: its first control
            } else {
                page.press()
            }
            return true
        case .right:
            if side == .sidebar, sidebar.highlighted != nil {
                page.move(1)
            } else {
                // Along a row of several (tiles); else it changes nothing.
                _ = page.adjust(1) || page.moveInRow(1)
            }
            return true
        case .left:
            if side == .sidebar { return true }
            if page.adjust(-1) || page.moveInRow(-1) { return true }
            sidebar.highlightCurrent() // back to the sidebar, on the page shown
            return true
        }
    }
}
