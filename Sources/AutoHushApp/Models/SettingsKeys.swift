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
/// pointer moves the highlight to its side too. Tab and Shift-Tab go
/// control by control, a row of several one after the other (B,
/// 2026-11-09), across both sides as one loop (`tab`, K1, 2026-11-10),
/// the page's search too while it shows, after Back and Forward (K3; the
/// user's order, 2026-11-10). ↑ ↓ and Tab go on from the
/// control with the keyboard's focus, on its side (W9). A control that has the focus takes Return, Space,
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
    /// The keyboard's focus lets go, once ↑, ↓, Tab or a jump moved the
    /// highlight (on from it: `KeyHighlight.focused`): one at a time (set
    /// by the window).
    var dropFocus: @MainActor () -> Void = {}
    /// The page's search takes the keyboard, if one shows (Sound Sources'
    /// while open): Tab comes round to it (`tab`); `false` with none. Set
    /// by the window.
    var focusSearch: (@MainActor () -> Bool)?
    /// The page shown next lights its first control once it's drawn
    /// (`SettingsModel.shownPageTakesHighlight`): → on a sidebar row whose
    /// page isn't shown. Set by the window.
    var showsFirstOfNextPage: @MainActor () -> Void = {}

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

    /// The keys move in the sidebar: it has the highlight, or, with nothing
    /// highlighted, the keyboard's focus (macOS's ⌃Tab put it on a row:
    /// the keys go on from there, W9).
    private var inSidebar: Bool {
        side == .sidebar && sidebar.highlighted != nil || !isLit && sidebar.focused != nil
    }

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
            if inSidebar {
                sidebar.move(step)
                showSidebarPage()
            } else {
                // The sidebar let go of it (the pointer left): the page's.
                side = .page
                page.move(step)
            }
            dropFocus()
            return true
        case .tab, .backTab:
            tab(key == .tab ? 1 : -1)
            return true
        case .pageUp, .pageDown, .home, .end:
            guard let jump = key.jump else { return false }
            if inSidebar {
                sidebar.jump(jump)
                showSidebarPage()
            } else {
                side = .page
                page.jump(jump)
            }
            dropFocus()
            return true
        case .returnKey, .space:
            if side == .sidebar, sidebar.highlighted != nil {
                if sidebar.highlightedIsShown {
                    page.move(1) // into the page: its first control
                } else {
                    sidebar.press() // the foot's link, or the page of a row Tab stopped on
                }
            } else if key == .space {
                page.select()
            } else {
                page.press()
            }
            return true
        case .right:
            if side == .sidebar, sidebar.highlighted != nil {
                if sidebar.highlightedStandsForShown, !sidebar.highlightedIsShown {
                    // A lit row whose page isn't shown (lit by Tab, or by the
                    // pointer resting on it): its page shows, as Return shows
                    // it, and its first control lights up once it's drawn
                    // (R3 of the K1 review, 2026-11-10: → went into the page
                    // shown, another row's; F3, the user, 2026-11-10: the
                    // pointer's row too, what's lit being what the keys act on).
                    showsFirstOfNextPage()
                    sidebar.press()
                } else {
                    page.move(1)
                }
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

    /// Tab (1) or Shift-Tab (-1): control by control through the side the
    /// highlight (or the focus) is on, then across into the other, as one
    /// loop: the sidebar's pages and its link, then the page in reading
    /// order: Back and Forward over it, its search if one shows, the page's
    /// controls, and round (K1, the user, 2026-11-10: "Cross the sides", as
    /// System Settings with keyboard navigation on; K3: "Into the field
    /// too"; the search between the toolbar and the page, the user's order,
    /// 2026-11-10: `stopsAroundSearch`). A sidebar row Tab stops on is
    /// highlighted, its page left as it is, unlike ↑ and ↓: shown at once,
    /// Tab out of the sidebar would always go into the last row's page
    /// (About's), never another's; Return or Space shows it, → shows it
    /// and goes into it (R3).
    private func tab(_ step: Int) {
        let around = stopsAroundSearch
        if inSidebar {
            side = .sidebar
            if !sidebar.step(step, wraps: false) {
                // Past the sidebar's end: into the page, its search first going forward when nothing's over it.
                if step > 0, around.over.isEmpty, let focusSearch, focusSearch() { return clear() }
                if !page.stepIn(step) { sidebar.stepIn(step) } // a page with nothing to stop on: round
            }
        } else {
            side = .page
            // Between the stops over the page and the rest: its search, if one shows.
            if let current = page.highlighted ?? page.focused,
               step > 0 ? current == around.over.last : current == around.under.first,
               let focusSearch, focusSearch() { return clear() }
            if !page.step(step, wraps: false), !sidebar.stepIn(step) { page.stepIn(step) }
        }
        dropFocus()
    }

    /// The page's stops in Tab's order, split where its search comes: over
    /// it, Back and Forward (the toolbar over the page, `HighlightBand.top`);
    /// under it, the rest, from the search's ✕, Sort by and Reverse order on
    /// its row (the user's order, 2026-11-10: R1 had Tab from the search go
    /// up to Back).
    private var stopsAroundSearch: (over: [UUID], under: [UUID]) {
        let stops = page.tabStops
        let isOver = { (id: UUID) in self.page.controls[id]?.band == .top }
        return (stops.filter(isOver), stops.filter { !isOver($0) })
    }

    /// Shift-Tab in the page's search: the loop's stop before it (`tab`),
    /// Forward or Back over the page, else the sidebar's last (its link).
    func backTabFromSearch() {
        if let over = stopsAroundSearch.over.last { return page.highlight(over, in: page.rows) }
        if !sidebar.stepIn(-1) { page.stepIn(-1) }
    }

    /// Tab in the page's search: the loop's stop after it (`tab`), the
    /// first under it (the search's ✕); with none, the sidebar's first.
    func tabFromSearch() {
        if let under = stopsAroundSearch.under.first { return page.highlight(under, in: page.rows) }
        if !sidebar.stepIn(1) { page.stepIn(1) }
    }

    /// The page of the sidebar's highlighted row shows at once; the foot's
    /// link opens only from Return or Space.
    private func showSidebarPage() {
        if sidebar.highlightedStandsForShown { sidebar.press() }
    }
}
