/// The check's helper as Add an App uses it: it runs the check, and tells
/// about an app that needs a launch option and reopens it with it.
/// `PlayerCheckHelper` is AutoHush's own; tests stand in.
@MainActor
protocol CheckHelping {
    /// Whether the app runs with the launch option it needs; `nil` when it
    /// needs none or isn't running.
    func runsWithLaunchOption(_ app: CheckableApp) async -> Bool?
    /// Quits it and opens it again with its launch option; whether it did.
    func reopenWithLaunchOption(_ app: CheckableApp) async -> Bool
    /// Starts the check, each line of its report to `onLine`; `taps` false
    /// in AntiDot mode. `nil` when it couldn't start.
    func startCheck(_ app: CheckableApp, taps: Bool, onLine: @escaping @MainActor @Sendable (String) -> Void) -> (any CheckRunning)?
}
