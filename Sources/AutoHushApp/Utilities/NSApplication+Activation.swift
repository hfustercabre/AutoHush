import AppKit

extension NSApplication {
    /// Makes AutoHush the active app.
    ///
    /// macOS 14 ignores `activate()` from a menu bar app that isn't active:
    /// a window opened from the menu showed without the focus, which stayed
    /// with the app in front (14.4, 2026-10-16). There the older call, which
    /// it still honors, is used.
    func becomeActive() {
        if #available(macOS 15, *) {
            activate()
        } else {
            (self as LegacyActivation).activateIgnoringOtherApps()
        }
    }
}

/// Reaches the call macOS 14 deprecated without its warning (builds treat
/// warnings as errors).
@MainActor private protocol LegacyActivation {
    func activateIgnoringOtherApps()
}

extension NSApplication: LegacyActivation {
    @available(macOS, deprecated: 14.0)
    fileprivate func activateIgnoringOtherApps() {
        activate(ignoringOtherApps: true)
    }
}
