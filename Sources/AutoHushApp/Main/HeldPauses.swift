import Foundation

/// Monitoring that can be stopped: a player's `MonitoringPipeline`.
@MainActor
protocol StoppableMonitoring: AnyObject {
    func stop()
}

extension MonitoringPipeline: StoppableMonitoring {}

/// The monitoring of players AutoHush held paused when the user chose
/// another. Each runs on only to end its own pause, as it would have (the
/// other apps stop: its player plays again), and stops once its player is
/// anything but paused by it: played again, or taken over by the user. A
/// player chosen again is taken back (`takeBack`); the Mac sleeping forgets
/// them all (`stopAll`), as any pause then (decision S2).
@MainActor
final class HeldPauses {
    private struct Held {
        let token: UUID
        let bundleID: String
        let monitoring: any StoppableMonitoring
    }

    private var held: [Held] = []

    var isEmpty: Bool { held.isEmpty }

    /// `monitoring` (its updates come with `token`) holds `bundleID`'s
    /// player paused: it runs on.
    func keep(_ monitoring: any StoppableMonitoring, token: UUID, bundleID: String) {
        held.removeAll { $0.bundleID == bundleID }
        held.append(Held(token: token, bundleID: bundleID, monitoring: monitoring))
    }

    /// An update from the monitoring with `token`: `false` when it isn't one
    /// kept here (the current monitoring's, for the app). A kept one stops
    /// once its player is no longer paused by it.
    func follow(_ update: MonitoringPipeline.StatusUpdate, from token: UUID) -> Bool {
        guard let index = held.firstIndex(where: { $0.token == token }) else { return false }
        if case .playback(let state) = update, state != .pausedByMonitor, state != .unknown {
            held.remove(at: index).monitoring.stop()
        }
        return true
    }

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
    }
}
