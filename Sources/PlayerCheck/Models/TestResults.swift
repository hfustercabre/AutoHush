import CheckedPlayers
import PlayerCheckKit

/// Each way's results, for the report and the result file.
@MainActor enum TestResults {
    /// Each way's result in the first window state tested (visible), or in
    /// the only run when there were no states.
    static var first: [Way: TrialResult] = [:]
    /// Each way's result in each window state, and why it failed there, for
    /// "Ways to Control It".
    static var byState: [Way: [(state: WindowState, result: TrialResult, why: String)]] = [:]
    /// The window states a way couldn't be tried in, and why: the Now
    /// Playing item missing from the menu bar in one state while there in
    /// others says nothing about the app, so that state isn't counted
    /// against the panel.
    static var untested: [Way: [WindowState: String]] = [:]
    /// Why a way wasn't tried, for "Ways to Control It".
    static var notTried = readOnly ? "not tried: read only" : "not tried"
}
