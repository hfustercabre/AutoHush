import Foundation
import CheckedPlayers

/// The apps on the Mac as Add an App sees them: those it offers, one picked
/// on the disk, what each is built with, whether it runs, is still there
/// and plays, and opening it. `AppReader` reads them live; tests stand in.
@MainActor
protocol AppReading {
    /// The apps it offers (`CheckableApps`).
    func listApps() async -> [CheckableApp]
    /// The app at a place picked on the disk (Other App…), or why it can't be checked.
    func app(at url: URL) -> Result<CheckableApp, OtherAppProblem>
    func traits(ofAppAt url: URL) -> CheckedAppTraits
    func isRunning(_ bundleID: String) -> Bool
    /// Whether the app is still where it was found.
    func appExists(at url: URL) -> Bool
    /// Opens it in the background (with its launch option when it needs
    /// one); whether it did.
    func open(_ app: CheckableApp, withLaunchOption: Bool) async -> Bool
    /// Whether it plays now, as the check judges it (`AppPlaying`).
    func isPlaying(_ app: CheckableApp, traits: CheckedAppTraits) async -> Bool
    /// Whether it has a window the check can reach, as the check tells it
    /// (`AppWindows.hasWindowWithinReach`).
    func hasWindowWithinReach(_ app: CheckableApp) async -> Bool
}
