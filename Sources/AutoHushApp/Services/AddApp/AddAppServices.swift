import Foundation
import CheckedPlayers

/// What adding an app does outside the model: the app's are live, tests'
/// stand in for them.
@MainActor
struct AddAppServices {
    var listApps: @MainActor () async -> [CheckableApp]
    /// The app at a place picked on the disk (Other App…), or why it can't be checked.
    var appAt: @MainActor (URL) -> Result<CheckableApp, OtherAppProblem> = { _ in .failure(.notAnApp) }
    /// The check's helper is in the app: without it, nothing can be checked.
    var hasHelper = true
    /// The window that lists the apps to choose (the first step's).
    var showChooser: @MainActor () -> Void = {}
    var closeChooser: @MainActor () -> Void = {}
    var traits: @MainActor (URL) -> CheckedAppTraits
    var isRunning: @MainActor (String) -> Bool
    /// Whether the app is still where it was found.
    var exists: @MainActor (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    /// Opens it in the background (with its launch option when it needs
    /// one); whether it did.
    var open: @MainActor (CheckableApp, _ withLaunchOption: Bool) async -> Bool
    /// Whether it runs with the launch option it needs; `nil` when it needs
    /// none or isn't running.
    var runsWithLaunchOption: @MainActor (CheckableApp) async -> Bool?
    /// Quits it and opens it again with its launch option; whether it did.
    var reopen: @MainActor (CheckableApp) async -> Bool
    var permissions: @MainActor (CheckableApp, _ scriptable: Bool) async -> CheckPermissions
    var request: @MainActor (CheckPermission, CheckableApp, CheckPermissions) async -> Void
    /// AntiDot mode is on: no audio taps (nothing listens to the app, and
    /// it can't be muted).
    var antiDot: @MainActor () -> Bool = { false }
    /// Whether it plays now, as the check judges it (`AppPlaying`).
    var isPlaying: @MainActor (CheckableApp, CheckedAppTraits) async -> Bool
    /// Starts the check; `taps` false in AntiDot mode.
    var startCheck: @MainActor (CheckableApp, _ taps: Bool, _ onLine: @escaping @MainActor @Sendable (String) -> Void) -> (any CheckRunning)?
    /// The warning before the check (W6), whose Start calls `startCheck()`.
    var showWarning: @MainActor () -> Void
    var closeWarning: @MainActor () -> Void = {}
    /// The check's panel and shade, while it runs.
    var checkStarted: @MainActor (CheckableApp) -> Void
    var checkEnded: @MainActor () -> Void
    /// Shows the newest check's log (after one couldn't finish).
    var showLog: @MainActor () -> Void = {}
    /// Quits AutoHush and opens it again (Audio Recording allowed in System
    /// Settings applies from the next launch).
    var reopenAutoHush: @MainActor () -> Void = {}
    /// Where a finished check's result is kept until it's used or replaced
    /// (a reopen of AutoHush, or the window closed, doesn't lose it).
    var keptChecks: KeptCheckStore = KeptCheckStore()
    /// Keeps what the check found and makes the app the player; `asksToReopen`
    /// false once the user skipped reopening it.
    var use: @MainActor (CheckResult, _ asksToReopen: Bool) -> Void
    var close: @MainActor () -> Void
    var now: @MainActor () -> Date = { Date() }
    var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
}
