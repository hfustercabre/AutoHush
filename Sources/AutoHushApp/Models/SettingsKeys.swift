import Foundation

/// Settings' highlight, as the menu's (the user, 2026-10-18: "Lets add the
/// same over and arrows navigation system to the Settings Window"), on two
/// sides: the sidebar's pages and the page's controls, one highlighted at a
/// time (`KeyHighlight` each). ↑ and ↓ move within the sidebar while it
/// holds the highlight, each page showing at once as in System Settings,
/// else through the page, row by row; Page Up and Page Down, Home and End
/// jump through the same side (`KeyHighlight.jump`, 2026-11-01). → or Return goes from the sidebar
/// into the page; ← goes back, unless the highlight is on a slider or a
/// choice, which ← and → change, or in a row of several (tiles), which they
/// move along first. Return or Space presses the page's control. The
/// pointer moves the highlight to its side too. Tab and Shift-Tab move as
/// ↓ and ↑ (`HighlightKey`), and a control that has the focus takes Return, Space,
/// ← and → itself while nothing is highlighted (the full check, 2026-10-18);
/// once something is, its tint hides the focus's (K9), and it takes them
/// (N6, 2026-11-06: whatever shows the tint gets the keys). Delete
/// removes the highlighted control if it can be (an added app's tile).
/// The sidebar's foot has the support link: ↑ and ↓ stop on it without
/// opening it, Return or Space opens it (N7, 2026-11-06).
/// Keys with nothing to act on do nothing, without a beep.
@MainActor
final class SettingsKeys {
    enum Side { case sidebar, page }

    let sidebar = KeyHighlight()
    let page = KeyHighlight()
    /// The side the highlight is on, or goes to first: the page.
    private(set) var side: Side = .page

    init() {
        // Either side lit hides the keyboard's focus on both (K9).
        sidebar.partner = page
        page.partner = sidebar
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

    /// Something is highlighted, on either side: its tint hides the focus's (K9).
    var isLit: Bool { sidebar.highlighted != nil || page.highlighted != nil }

    /// The page shown changed (a click on its row, Back or Forward, ↑ or ↓
    /// in the sidebar): the sidebar's highlight follows it while the keys
    /// put it there; the pointer's stays under the pointer, the tint alone,
    /// with neither VoiceOver's cursor nor Zoom moved (N1, 2026-11-06: a
    /// clicked row took the keys' outline while the pointer rested on it).
    func pageChanged() {
        if sidebar.isLitByKeys { sidebar.highlightCurrent() }
    }

    /// Handles `key`; `false` leaves it to the window: Return, Space, ←
    /// and → while a control has the keyboard's focus (`controlHasFocus`)
    /// and nothing is highlighted.
    @discardableResult func handle(_ key: HighlightKey, controlHasFocus: Bool = false) -> Bool {
        if controlHasFocus, !isLit, [.returnKey, .space, .left, .right].contains(key) { return false }
        switch key {
        case .delete:
            return page.delete()
        case .up, .down:
            let step = key == .down ? 1 : -1
            if side == .sidebar, sidebar.highlighted != nil {
                sidebar.move(step)
                showSidebarPage()
            } else {
                // The sidebar let go of it (the pointer left): the page's.
                side = .page
                page.move(step)
            }
            return true
        case .pageUp, .pageDown, .home, .end:
            guard let jump = key.jump else { return false }
            if side == .sidebar, sidebar.highlighted != nil {
                sidebar.jump(jump)
                showSidebarPage()
            } else {
                side = .page
                page.jump(jump)
            }
            return true
        case .returnKey, .space:
            if side == .sidebar, sidebar.highlighted != nil {
                if sidebar.highlightedStandsForShown {
                    page.move(1) // into the page: its first control
                } else {
                    sidebar.press() // the foot's link
                }
            } else if key == .space {
                page.select()
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

    /// The page of the sidebar's highlighted row shows at once; the foot's
    /// link opens only from Return or Space.
    private func showSidebarPage() {
        if sidebar.highlightedStandsForShown { sidebar.press() }
    }
}
