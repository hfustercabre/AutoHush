import CheckedPlayers

extension CheckResult.WindowState {
    /// Where Chromium treats an Electron app's page as hidden, unless the app
    /// was opened with `LaunchOption.occludedWindows`: its window fully out
    /// of view, but not minimized or hidden.
    static let outOfView: Set<WindowState> = [.covered, .otherDesktop, .otherDesktopCovered, .fullScreen]
}
