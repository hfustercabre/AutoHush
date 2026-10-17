import AppKit

extension NSWindow {
    /// Shows it in front of every app's windows, on the desktop the user is
    /// on, and makes AutoHush the active app, in the Dock while the window
    /// is open (`DockPresence`).
    ///
    /// macOS may not let AutoHush become active when it asks: at its first
    /// launch, opened from System Settings' Open Anyway, or when a window
    /// opens by itself while the user is in System Settings allowing a
    /// permission. An inactive app's window would then open behind the
    /// active app's, where the user can't see it.
    ///
    /// It isn't made to follow the user from desktop to desktop for good
    /// (`.moveToActiveSpace`): macOS then gives a desktop the user comes
    /// back to to the app that was active there before, and raises its
    /// windows over AutoHush's. Open on another desktop, it follows only
    /// while it shows (`comeToActiveSpace`). Over a full-screen app, macOS
    /// takes the user to the desktop it opens on.
    func showInFront() {
        DockPresence.windowWillShow(self)
        if isMiniaturized { deminiaturize(nil) }
        comeToActiveSpace()
        NSApp.becomeActive()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    /// On screen, minimized in the Dock, or hidden with AutoHush (⌘H): open
    /// either way. macOS counts the last two as not visible.
    var isOpen: Bool { isVisible || isMiniaturized || DockPresence.isShown(self) }

    /// Brings it in front of other apps' windows, on the desktop the user is
    /// on, without making it key or AutoHush active.
    func bringForward() {
        comeToActiveSpace()
        orderFrontRegardless()
    }

    /// Open on another desktop (the user moved, or another app took them
    /// there), it's taken off it, to come back on the one they're on: taken
    /// off alone, AutoHush becoming active took the user to that desktop
    /// (macOS 27, 2026-10-17), so it follows them for a second.
    private func comeToActiveSpace() {
        guard isVisible, !isOnActiveSpace else { return }
        orderOut(nil)
        guard collectionBehavior.insert(.moveToActiveSpace).inserted else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { _ = self?.collectionBehavior.remove(.moveToActiveSpace) }
        }
    }
}
