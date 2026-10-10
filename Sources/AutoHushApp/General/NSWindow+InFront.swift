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
    /// It isn't made to follow the user from desktop to desktop
    /// (`.moveToActiveSpace`): macOS then gives a desktop the user comes
    /// back to to the app that was active there before, and raises its
    /// windows over AutoHush's. Taken off another desktop before it shows
    /// is enough to open it on the user's.
    func showInFront() {
        DockPresence.windowWillShow(self)
        if isMiniaturized { deminiaturize(nil) }
        comeToActiveSpace()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate()
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
    /// there), it's taken off it, to come back on the one they're on.
    private func comeToActiveSpace() {
        if isVisible, !isOnActiveSpace { orderOut(nil) }
    }
}
