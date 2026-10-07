import AppKit

extension NSWindow {
    /// Shows it in front of every app's windows, on the desktop the user is
    /// on, and makes AutoHush the active app.
    ///
    /// macOS may not let AutoHush become active when it asks: at its first
    /// launch, opened from System Settings' Open Anyway, or when a window
    /// opens by itself while the user is in System Settings allowing a
    /// permission. An inactive app's window would then open behind the
    /// active app's, where the user can't see it.
    func showInFront() {
        collectionBehavior.insert(.moveToActiveSpace)
        comeToActiveSpace()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        NSApp.activate()
    }

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
