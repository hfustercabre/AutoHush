import CheckedPlayers

extension CheckResult.WindowState {
    /// Where Chromium treats an Electron app's page as hidden, unless the app
    /// was opened with `LaunchOption.occludedWindows`: its window fully out
    /// of view, but not minimized or hidden.
    package static let outOfView: Set<CheckResult.WindowState> = [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen]

    /// On another desktop, which the check reaches with Mission Control's
    /// desktop shortcuts (`DesktopShortcuts`): out of its reach while
    /// they're off (I1, 2026-10-31).
    package var needsDesktopShortcuts: Bool {
        self == .otherDesktop || self == .otherDesktopCovered
    }
}
