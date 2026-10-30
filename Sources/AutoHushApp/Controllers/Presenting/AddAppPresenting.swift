/// What Add an App's model shows through the feature that owns it
/// (`AddAppFeature`): the list of apps, the warning before a check, the
/// check's panel (with the Mac's output muted around it when the app can't
/// be muted alone), the check's log, System Settings' Menu Bar pane, and
/// its own window's close. Tests stand in.
@MainActor
protocol AddAppPresenting: AnyObject {
    /// The window that lists the apps to choose (the first step's).
    func showChooser()
    func closeChooser()
    /// The warning before the check (W6), whose Start calls `startCheck()`.
    func showWarning()
    func closeWarning()
    /// The check of `app` runs: its panel shows until `checkEnded()`.
    func checkStarted(_ app: CheckableApp)
    func checkEnded()
    /// Whether the Mac's output can be muted now: the check mutes it when it
    /// can't mute only the app (`AddAppModel.checkMuting`).
    var canMuteOutput: Bool { get }
    /// Whether there's a check's log to show.
    var hasCheckLog: Bool { get }
    /// Shows the newest check's log (after one couldn't finish).
    func showCheckLog()
    /// Opens System Settings where Now Playing is shown in the menu bar.
    func openMenuBarSettings()
    func closeWindow()
}
