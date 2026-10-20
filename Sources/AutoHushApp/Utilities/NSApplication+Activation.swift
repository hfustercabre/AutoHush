import AppKit

extension NSApplication {
    /// Makes AutoHush the active app.
    ///
    /// macOS ignores `activate()` from a menu bar app that isn't active: a
    /// window opened from the menu showed without the focus, which stayed
    /// with the app in front (14.4, 2026-10-16), and from the menu's panel
    /// on every version (macOS 27, 2026-10-17: Settings stayed behind, or on
    /// its desktop). The older call, which macOS still honors, is used: the
    /// SDK marks it only as to be deprecated, so it brings no warning.
    func becomeActive() {
        activate(ignoringOtherApps: true)
    }
}
