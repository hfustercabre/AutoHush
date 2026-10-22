import CheckedPlayers

/// What Add an App needs from the rest of AutoHush, which AppDelegate does:
/// the players it supports (never offered or checked), AntiDot mode, an
/// app's permissions read and asked for by the chosen player's rules, the
/// player held while a check runs, reopening AutoHush, and the app checked
/// made the player.
@MainActor
protocol AddAppHost: AnyObject {
    /// The players AutoHush supports as apps.
    var supportedApps: [PlayerOption] { get }
    /// AntiDot mode is on: no audio taps (nothing listens to the app, and
    /// it can't be muted).
    var isAntiDot: Bool { get }
    /// Turns AntiDot mode off (the last step, when nothing can be used in it).
    func turnOffAntiDot()
    /// What the check of `app` needs, as it stands now (`PermissionCenter`).
    func checkPermissions(_ app: CheckableApp, scriptable: Bool) async -> CheckPermissions
    /// A permission's Allow…, as anywhere else.
    func requestCheckPermission(_ permission: CheckPermission, app: CheckableApp, current: CheckPermissions) async
    /// While a check runs (`true`), AutoHush resumes nothing; as it ends, as usual.
    func holdsPlayerForCheck(_ held: Bool)
    /// Quits AutoHush and opens it again: Audio Recording allowed in System
    /// Settings applies from the next launch.
    func reopenForAudioRecording()
    /// Quits AutoHush and opens it again, Add an App with it: a running app
    /// learns of an Accessibility change only when macOS says so, which it
    /// doesn't always (`AddAppModel.accessibilityNeedsReopen`).
    func reopenKeepingAddApp()
    /// Keeps what the check found and makes the app the player; `asksToReopen`
    /// false once the user skipped reopening it.
    func useCheckedApp(_ result: CheckResult, asksToReopen: Bool)
}
