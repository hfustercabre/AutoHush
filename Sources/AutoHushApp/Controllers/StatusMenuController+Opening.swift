import AppKit
import SwiftUI

// StatusMenuController: opening and closing the menu, its window placed
// under the menu bar item.
extension StatusMenuController {
    /// A click on the menu bar item opens the menu, and closes it while
    /// it's open, as macOS's own menu bar items do (the user, 2026-10-18).
    /// The click that closed it from outside, over the item (`watchWhileOpen`),
    /// mustn't open it again at once.
    @objc func statusItemClicked() {
        if isMenuOpen {
            close()
        } else if let closed = lastClosedByClick, now().timeIntervalSince(closed) < 0.4 {
            lastClosedByClick = nil
        } else {
            open()
        }
    }

    /// Opens the menu under its menu bar item, the app first bringing the
    /// status up to date (`AppActions.menuWillOpen`). `showsPanel` off: the
    /// menu is ready and counts as open, but nothing shows (tests).
    func open(showsPanel: Bool = true) {
        guard !isMenuOpen else { return }
        actions?.menuWillOpen()
        prepareContent()
        isMenuOpen = true
        watchOtherWindows()
        guard showsPanel else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Its content as it opens, measured before it's placed.
        panel.contentView?.layoutSubtreeIfNeeded()
        placePanel(panel)
        panel.orderFrontRegardless()
        panel.makeKey()
        // As macOS's menus open: nothing focused, even with keyboard
        // navigation on, so Space doesn't toggle Auto-Pause straight away.
        panel.makeFirstResponder(nil)
        statusItem.button?.highlight(true)
        watchWhileOpen()
    }

    /// Closes the menu, at once: also before an alert, such as an update
    /// check's result, which can't show over it.
    func close() {
        guard isMenuOpen else { return }
        isMenuOpen = false
        sideOpenTask?.cancel()
        sideCloseTask?.cancel()
        sidePanel?.orderOut(nil)
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let spaceObserver { workspaceCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        if let keyWindowObserver { notificationCenter.removeObserver(keyWindowObserver) }
        keyWindowObserver = nil
    }

    private func makePanel() -> MenuPanel {
        let view = MenuPanelView(model: model, settings: settingsModel) { [weak self] in self?.contentHeightChanged($0) }
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.safeAreaRegions = [] // under the hidden title bar too
        // A size to lay out in before the panel has its own: with none, its
        // content measures nothing.
        hosting.frame = NSRect(x: 0, y: 0, width: menuContentWidth, height: 600)
        let panel = MenuPanel(content: hosting)
        // Escape closes the side window first, as a submenu, then the menu.
        panel.onCancel = { [weak self] in
            guard let self else { return }
            if model.openSide != nil { closeSide() } else { close() }
        }
        panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
        hosting.layoutSubtreeIfNeeded()
        contentHeight = max(contentHeight, hosting.fittingSize.height)
        return panel
    }

    /// Under the menu bar item, its left edge at the item's (kept on the
    /// screen), as tall as its content but never past the screen's bottom.
    private func placePanel(_ panel: MenuPanel) {
        guard let button = statusItem.button, let window = button.window,
              let screen = window.screen ?? NSScreen.main else { return }
        let item = window.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = Self.panelFrame(under: item, in: screen.visibleFrame, width: menuContentWidth, contentHeight: contentHeight)
        model.isCappedByScreen = Self.isCapped(height: frame.height, content: contentHeight)
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    /// The panel's frame under the menu bar item at `item`: its left edge at
    /// the item's, kept 6 pt inside the screen's `visible` part, 4 pt under
    /// it, as tall as its content but never past the screen's bottom.
    static func panelFrame(under item: NSRect, in visible: NSRect, width: CGFloat, contentHeight: CGFloat) -> NSRect {
        let x = min(max(item.minX, visible.minX + 6), visible.maxX - width - 6)
        let top = min(item.minY - 4, visible.maxY)
        let height = fittingHeight(contentHeight, top: top, in: visible)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    /// A height of `height` for a panel whose top edge is at `top`, but
    /// never past 6 pt above the screen's bottom (the rest scrolls).
    static func fittingHeight(_ height: CGFloat, top: CGFloat, in visible: NSRect) -> CGFloat {
        min(height, top - visible.minY - 6)
    }

    /// Whether a window `height` tall shows less than its `content`: the
    /// screen caps it, and only then does it show that more is below.
    static func isCapped(height: CGFloat, content: CGFloat) -> Bool {
        height < content.rounded() - 0.5
    }

    /// The content's height changed (a part folded or unfolded, the status
    /// line wrapped): the panel follows, animated while it shows, once its
    /// parts have all reported (a fold moves two of them in one pass).
    private func contentHeightChanged(_ height: CGFloat) {
        contentHeight = height
        guard isMenuOpen, panel?.isVisible == true, !followsContent else { return }
        followsContent = true
        RunLoop.main.perform { [weak self] in
            MainActor.assumeIsolated { self?.followContent() }
        }
    }

    private func followContent() {
        followsContent = false
        guard isMenuOpen, let panel, panel.isVisible, let screen = panel.screen else { return }
        let height = Self.fittingHeight(contentHeight, top: panel.frame.maxY, in: screen.visibleFrame)
        model.isCappedByScreen = Self.isCapped(height: height, content: contentHeight)
        panel.setContentHeight(height, animated: !reducesMotion())
    }

    /// Closes the menu on a click outside it (in another app, or another of
    /// AutoHush's windows); follows Option.
    private func watchWhileOpen() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeForClickElsewhere() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.flagsChanged), handler: { [weak self] event in
            let isFlags = event.type == .flagsChanged
            let optionHeld = event.modifierFlags.contains(.option)
            let windowNumber = event.windowNumber
            MainActor.assumeIsolated {
                guard let self else { return }
                if isFlags {
                    self.model.isOptionHeld = optionHeld
                } else if windowNumber != self.panel?.windowNumber, windowNumber != self.sidePanel?.windowNumber,
                          windowNumber != self.statusItem.button?.window?.windowNumber {
                    self.close()
                }
            }
            return event
        }) { monitors.append(local) }
    }

    /// A click outside the menu closes it. One on the menu bar item itself
    /// reaches the item too, as its next click: noted, so it doesn't open
    /// the menu again (`statusItemClicked`). Only that one (the full check,
    /// 2026-10-18: a quick click elsewhere and then on the icon opened nothing).
    func closeForClickElsewhere() {
        close()
        if let item = itemFrame?() ?? statusItem.button?.window?.frame, item.contains(pointerLocation()) {
            lastClosedByClick = now()
        }
    }

    /// Closes the menu as another window becomes key (one of AutoHush's, or
    /// an alert, that a choice in the menu brought forward), or on another
    /// desktop.
    private func watchOtherWindows() {
        spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.close() } }
        keyWindowObserver = notificationCenter.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            // Its identity, which can cross into the main actor (the window can't).
            let window = (note.object as? NSWindow).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let self, let window, window != self.panel.map(ObjectIdentifier.init),
                      window != self.sidePanel.map(ObjectIdentifier.init),
                      let key = NSApp.windows.first(where: { ObjectIdentifier($0) == window }),
                      Self.closesMenu(becomingKey: key, statusItemWindow: self.statusItem.button?.window) else { return }
                self.close()
            }
        }
    }

    /// Whether `window` becoming key is another window coming forward: a
    /// visible one, not the menu bar item's own (VoiceOver's press on a row
    /// makes that one key, 2026-10-18).
    static func closesMenu(becomingKey window: NSWindow, statusItemWindow: NSWindow?) -> Bool {
        window.isVisible && window !== statusItemWindow && window.level != .statusBar
    }
}
