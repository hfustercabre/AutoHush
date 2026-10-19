/// The menu bar's Now Playing panel, opened, read and pressed through
/// Accessibility: the last way to pause or play an app nothing else
/// controls, since it opens on screen for about half a second and takes the
/// keyboard meanwhile (the user, 2026-10-15: only if nothing else works).
/// Calls block. A protocol, so tests can stand in for it.
protocol NowPlayingPanel: Sendable {
    /// Opens the panel, then calls `pick` with its rows: the row it returns
    /// has its Play/Pause pressed. The panel is closed again either way.
    /// `nil` when the panel couldn't be opened; else whether a row was pressed.
    func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool?
    /// Whether Now Playing is in the menu bar: hidden in System Settings,
    /// macOS removes it altogether (measured on macOS 27, 2026-10-15).
    func isInMenuBar() -> Bool
}
