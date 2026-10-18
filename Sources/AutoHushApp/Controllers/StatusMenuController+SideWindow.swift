import AppKit
import SwiftUI

// StatusMenuController: the side window beside the menu (W2, the user's
// pick, 2026-10-18): the players, or the ignored apps, as a submenu.
extension StatusMenuController {
    /// Opens the side window the model asks for beside the menu, level with
    /// its row, or closes it. Escape closes it first, then the menu.
    func showSide() {
        guard isMenuOpen, let panel, panel.isVisible, let part = model.openSide else {
            if sidePanel?.isVisible == true {
                sidePanel?.orderOut(nil)
                if isMenuOpen { panel?.makeKey() }
            }
            return
        }
        let side = sidePanel ?? makeSidePanel()
        sidePanel = side
        // VoiceOver names it by its part (the full check, 2026-10-18).
        side.title = part == .players ? MenuMediaPlayerView.title : MenuIgnoredAppsView.title
        side.contentView?.layoutSubtreeIfNeeded()
        placeSide(side, beside: panel)
        side.orderFrontRegardless()
        // The menu keeps the keyboard, so its switches stay drawn active
        // (AppKit draws a window that isn't key as inactive): typing goes to
        // the players' search, ↑ ↓ Return to their list (`handleKey`). Only
        // VoiceOver moves into the side window, to read it, and the search
        // when it needs the keyboard itself (`searchTakesKeyboard`).
        side.takesKey = NSWorkspace.shared.isVoiceOverEnabled
        if side.takesKey { side.makeKey() } else { panel.makeKey() }
    }

    /// Opens `part`'s side window, closing the other.
    func open(_ part: MenuSidePart) {
        model.isChoosingPlayer = part == .players
        model.showsIgnoredApps = part == .ignoredApps
        model.playerSearch = ""
        model.sideKeyboard.clear()
        // Listed as they are now, fixed while it's open.
        if part == .ignoredApps { model.listedIgnoredApps = status.ignoredApps }
        showSide()
    }

    /// Closes the side window, the menu staying open.
    func closeSide() {
        model.isChoosingPlayer = false
        model.showsIgnoredApps = false
        model.playerSearch = ""
        model.sideKeyboard.clear()
        sideCloseTask?.cancel()
        showSide()
    }

    /// The players' search takes the keyboard itself (the full check,
    /// 2026-10-18): the side window becomes key, its field focused, so input
    /// methods and dead keys compose there, and a click in it shows the
    /// caret. `event`, a key typed while the menu had the keyboard, is typed
    /// into it once it has the focus. The menu's switches are drawn inactive
    /// meanwhile, as in any window that isn't key.
    func searchTakesKeyboard(replaying event: NSEvent? = nil) {
        guard model.isChoosingPlayer, let side = sidePanel, side.isVisible else { return }
        side.takesKey = true
        side.makeKey()
        model.searchFocus += 1
        guard let event else { return }
        let pause = pause
        Task { [weak side] in
            await pause(0.05) // SwiftUI focuses the field in its next update
            side?.sendEvent(event)
        }
    }

    /// The pointer came onto a row that opens a side window (`inside`) or
    /// left it: resting on it a moment opens it, as a submenu.
    func hoverSideRow(_ part: MenuSidePart, _ inside: Bool) {
        if inside {
            hoveredSideRow = part
            sideOpenTask?.cancel()
            let pause = pause
            sideOpenTask = Task { [weak self] in
                await pause(Self.sideOpenDelay)
                guard !Task.isCancelled, let self, self.isMenuOpen, self.hoveredSideRow == part,
                      self.model.openSide != part else { return }
                self.open(part)
            }
        } else if hoveredSideRow == part {
            hoveredSideRow = nil
            sideOpenTask?.cancel()
        }
    }

    /// The pointer came onto a part of the menu: another than the open side
    /// window's closes it after a moment, unless the pointer is on its way
    /// to it across other parts, as macOS's submenus (the user, 2026-10-18).
    func pointerEntered(_ section: MenuSection) {
        pointerSection = section
        guard let open = model.openSide else { return }
        guard section != open.section else {
            sideCloseTask?.cancel() // back on its row
            return
        }
        sideCloseTask?.cancel()
        let start = pointerLocation()
        let pause = pause
        sideCloseTask = Task { [weak self] in
            var from = start
            for _ in 0..<5 {
                await pause(Self.sideCloseDelay)
                guard !Task.isCancelled, let self, self.stillLeaving(open) else { return }
                let now = self.pointerLocation()
                guard let frames = self.frames, Self.isHeading(from: from, to: now, toward: frames.side, beside: frames.menu)
                else { break }
                from = now
            }
            guard !Task.isCancelled, let self, self.stillLeaving(open) else { return }
            self.closeSide()
        }
    }

    /// The side window `part` is open, and the pointer on another part of
    /// the menu than its row's, not in it.
    private func stillLeaving(_ part: MenuSidePart) -> Bool {
        isMenuOpen && model.openSide == part && pointerSection != part.section && !pointerIsInSide
    }

    /// The menu's and the side window's frames, while both show.
    private var frames: (menu: CGRect, side: CGRect)? {
        if let windowFrames { return windowFrames() }
        guard let panel, let side = sidePanel, side.isVisible else { return nil }
        return (panel.frame, side.frame)
    }

    /// The pointer went from `from` to `to` on its way to the side window
    /// (`side`, beside `menu`): nearer its edge, inside the triangle from
    /// where it was to that edge's corners, as macOS keeps a submenu open.
    nonisolated static func isHeading(from: CGPoint, to: CGPoint, toward side: CGRect, beside menu: CGRect) -> Bool {
        let edge = side.midX < menu.midX ? side.maxX : side.minX
        guard abs(to.x - edge) < abs(from.x - edge) else { return false }
        let a = from, b = CGPoint(x: edge, y: side.minY), c = CGPoint(x: edge, y: side.maxY)
        func cross(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        let d1 = cross(a, b, to), d2 = cross(b, c, to), d3 = cross(c, a, to)
        let negative = d1 < 0 || d2 < 0 || d3 < 0, positive = d1 > 0 || d2 > 0 || d3 > 0
        return !(negative && positive)
    }

    /// The pointer is over the side window.
    private var pointerIsInSide: Bool {
        frames?.side.contains(pointerLocation()) ?? false
    }

    private func makeSidePanel() -> MenuPanel {
        let view = MenuSidePanelView(model: model) { [weak self] in self?.sideHeightChanged($0) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.frame = NSRect(x: 0, y: 0, width: MenuSidePanelView.width, height: 600)
        let side = MenuPanel(content: hosting)
        side.onCancel = { [weak self] in self?.closeSide() }
        side.onKey = { [weak self] in self?.handleKey($0) ?? false }
        return side
    }

    private func placeSide(_ side: MenuPanel, beside panel: MenuPanel) {
        guard let part = model.openSide, let screen = panel.screen ?? NSScreen.main else { return }
        let rowTop = panel.frame.maxY - (model.sideRowTops[part] ?? 0)
        let frame = Self.sideFrame(rowTop: rowTop, menu: panel.frame, in: screen.visibleFrame,
                                   width: MenuSidePanelView.width, contentHeight: sideHeight)
        model.isSideCappedByScreen = Self.isCapped(height: frame.height, content: sideHeight)
        side.setFrame(frame, display: true)
        side.invalidateShadow()
    }

    /// The side window's frame: beside the menu, on its left (the menu sits
    /// near the screen's right edge) unless there's no room there, then on
    /// its right; its top level with the row that opened it (`rowTop`, the
    /// first row inside level with that row), as tall as its content but
    /// on the screen, moved up if it would go past the screen's bottom.
    static func sideFrame(rowTop: CGFloat, menu: NSRect, in visible: NSRect, width: CGFloat, contentHeight: CGFloat) -> NSRect {
        let gap: CGFloat = 6
        let x = menu.minX - gap - width >= visible.minX + 6 ? menu.minX - gap - width : menu.maxX + gap
        let height = min(contentHeight, visible.height - 12)
        let top = max(min(rowTop + 8, visible.maxY - 6), visible.minY + 6 + height)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// Its content's height changed (another side, a search): the window
    /// follows at the end of this pass, as the menu does (resized during
    /// SwiftUI's layout, its content kept a stale frame, 2026-10-18).
    private func sideHeightChanged(_ height: CGFloat) {
        sideHeight = height
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isMenuOpen, let panel = self.panel, let side = self.sidePanel, side.isVisible else { return }
                self.placeSide(side, beside: panel)
            }
        }
    }
}
