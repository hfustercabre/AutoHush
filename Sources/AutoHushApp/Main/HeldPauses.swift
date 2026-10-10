import Foundation

/// A player's monitoring, as `HeldPauses` keeps it: a `MonitoringPipeline`.
@MainActor
protocol HeldMonitoring: AnyObject {
    func stop()
    /// Stops, and waits until a faded-down player has its volume back.
    func stopAndRestoreVolume() async
    func setAutoPauseEnabled(_ enabled: Bool)
    func setIgnoredSources(_ ids: Set<String>)
}

extension MonitoringPipeline: HeldMonitoring {}

/// The monitoring of players AutoHush held paused when the user chose
/// another. Each runs on only to end its own pause, as it would have (the
/// other apps stop: its player plays again), and stops once its player is
/// anything but paused by it: played again, or taken over by the user. A
/// player chosen again is taken back (`choose`, `takesBack`); the Mac
/// sleeping forgets them all (`stopAll`), as any pause then (decision S2);
/// quitting hands them over (`bundleIDs`, `stopAndRestoreAll`).
@MainActor
final class HeldPauses {
    private struct Held {
        let token: UUID
        let bundleID: String
        let monitoring: any HeldMonitoring
        /// Started to take a handed-over pause over: what it reports before
        /// it has (the player's state as it found it) doesn't count.
        var awaitingTakeOver = false
    }

    private var held: [Held] = []
    /// The player taken back, whose next monitoring takes its pause over.
    private var pendingTakeBack: String?

    var isEmpty: Bool { held.isEmpty }
    /// The players held paused.
    var bundleIDs: [String] { held.map(\.bundleID) }

    /// The user chooses `bundleID` while `current` (its updates come with
    /// `token`) monitors `leaving`, holding its player paused when
    /// `holdsPause`: it's kept, and `true` says it must be left running. A
    /// player held paused that is chosen again is taken back.
    func choose(_ bundleID: String, leaving: String?, current: (any HeldMonitoring)?, token: UUID,
                holdsPause: Bool) -> Bool {
        var kept = false
        if holdsPause, let current, let leaving, leaving != bundleID {
            keep(current, token: token, bundleID: leaving)
            kept = true
        }
        if takeBack(bundleID) { pendingTakeBack = bundleID }
        return kept
    }

    /// Monitoring for `bundleID` starts: whether it takes a held pause back
    /// over, the player taken back last only. Any start ends the wait, so a
    /// pause is never taken over for a player AutoHush didn't pause.
    func takesBack(_ bundleID: String) -> Bool {
        defer { pendingTakeBack = nil }
        return pendingTakeBack == bundleID
    }

    /// `monitoring` (its updates come with `token`) holds `bundleID`'s
    /// player paused, or, `awaitingTakeOver`, starts to take a handed-over
    /// pause over: it runs on.
    func keep(_ monitoring: any HeldMonitoring, token: UUID, bundleID: String, awaitingTakeOver: Bool = false) {
        for replaced in held where replaced.bundleID == bundleID { replaced.monitoring.stop() }
        held.removeAll { $0.bundleID == bundleID }
        held.append(Held(token: token, bundleID: bundleID, monitoring: monitoring, awaitingTakeOver: awaitingTakeOver))
    }

    /// The monitoring with `token` found no pause to take over: it stops.
    func drop(_ token: UUID) {
        guard let index = held.firstIndex(where: { $0.token == token }) else { return }
        held.remove(at: index).monitoring.stop()
    }

    /// An update from the monitoring with `token`: `true` when it's one kept
    /// here and stays its own (the app applies the others). A kept one stops
    /// once its player is no longer paused by it. What AntiDot learned is
    /// the app's, whichever monitoring learned it.
    func takes(_ update: MonitoringPipeline.StatusUpdate, from token: UUID) -> Bool {
        guard let index = held.firstIndex(where: { $0.token == token }) else { return false }
        if held[index].awaitingTakeOver, case .playback(let state) = update {
            if state == .pausedByMonitor { held[index].awaitingTakeOver = false }
            return true
        }
        switch update {
        case .playback(let state) where state != .pausedByMonitor && state != .unknown:
            held.remove(at: index).monitoring.stop()
            return true
        case .learnedAssertions:
            return false
        default:
            return true
        }
    }

    /// The settings a held pause follows, as the chosen player's monitoring
    /// does: Auto-Pause off, or the playing app ignored, ends it at once.
    func setAutoPauseEnabled(_ enabled: Bool) { held.forEach { $0.monitoring.setAutoPauseEnabled(enabled) } }
    func setIgnoredSources(_ ids: Set<String>) { held.forEach { $0.monitoring.setIgnoredSources(ids) } }

    /// `bundleID`'s player is chosen again: its held monitoring stops, and
    /// `true` says the new one takes the pause back over.
    func takeBack(_ bundleID: String) -> Bool {
        guard let index = held.firstIndex(where: { $0.bundleID == bundleID }) else { return false }
        held.remove(at: index).monitoring.stop()
        return true
    }

    func stopAll() {
        held.forEach { $0.monitoring.stop() }
        held = []
        pendingTakeBack = nil
    }

    /// AutoHush quits: each stops, its player's volume back first (one
    /// fading in, say).
    func stopAndRestoreAll() async {
        let stopping = held
        held = []
        pendingTakeBack = nil
        for each in stopping { await each.monitoring.stopAndRestoreVolume() }
    }
}
