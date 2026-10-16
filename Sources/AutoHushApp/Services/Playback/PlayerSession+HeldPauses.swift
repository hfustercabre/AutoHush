import Foundation
import AutoHushKit

// PlayerSession: held pauses and the hand-over.
extension PlayerSession {
    /// The user chooses `bundleID`: see `choose(_:)`.
    func holdPause(for bundleID: String) {
        if heldPauses.choose(bundleID, leaving: player?.bundleID, current: monitoring, token: monitoringToken,
                             holdsPause: state.playback == .pausedByMonitor) {
            monitoring = nil // left running by the next start
        }
    }

    /// Hands the pauses AutoHush holds over to the AutoHush opened next: the
    /// chosen player's, and those of players held paused when another was
    /// chosen.
    func handOverPauses(now: Date) {
        let holdsChosen = state.playback == .pausedByMonitor
        guard holdsChosen || !heldPauses.isEmpty else { return }
        preferences.pauseHandover = PauseHandover(at: now, player: holdsChosen ? player?.bundleID : nil,
                                                  holdsChosen: holdsChosen, held: heldPauses.bundleIDs)
    }

    /// At launch: the players held paused when the AutoHush before this one
    /// quit, recently, other than the chosen one, whose own monitoring takes
    /// its pause back (`takesOverPause`); read once.
    func handedOverHeldPlayers(now: Date) -> [String] {
        guard let handover = preferences.pauseHandover, !handover.held.isEmpty,
              (0...Self.pauseHandoverMaxAge).contains(now.timeIntervalSince(handover.at)) else { return [] }
        let chosen = player?.bundleID
        preferences.pauseHandover = PauseHandover(at: handover.at, player: handover.player, holdsChosen: handover.holdsChosen,
                                                  held: handover.held.filter { $0 == chosen })
        return handover.held.filter { $0 != chosen }
    }

    /// Players held paused get their monitoring again, whatever the chosen
    /// player's does: it takes their pause over and ends it as it would have.
    func startHeldPauses(_ bundleIDs: [String]) {
        for bundleID in bundleIDs {
            guard let held = players.player(bundleID: bundleID) else { continue }
            let token = UUID()
            let monitoring = makeMonitoring(for: held, token: token)
            heldPauses.keep(monitoring, token: token, bundleID: bundleID, awaitingTakeOver: true)
            Task { [weak self, isAsleep] in
                // Played or quit by the user meanwhile: nothing to end.
                if await !monitoring.start(takingOverPause: true, asleep: isAsleep) { self?.heldPauses.drop(token) }
            }
        }
    }

    /// Whether monitoring takes over a pause handed over by the AutoHush before
    /// this one, at most `pauseHandoverMaxAge` before `now`, and for the
    /// player chosen now: the player may have changed meanwhile (one that
    /// didn't say, from AutoHush 0.8.2 and earlier, counts). Only the first
    /// monitoring asks; it starts after other copies have quit, so their
    /// hand-over is in by then.
    func takesOverPause(now: Date = Date()) -> Bool {
        guard !pauseHandoverChecked else { return false }
        pauseHandoverChecked = true
        guard let handover = preferences.pauseHandover else { return false }
        preferences.pauseHandover = nil
        guard (0...Self.pauseHandoverMaxAge).contains(now.timeIntervalSince(handover.at)) else { return false }
        // Held paused then, and chosen now: its own pause, back.
        if let chosen = player?.bundleID, handover.held.contains(chosen) { return true }
        guard handover.holdsChosen else { return false }
        if let paused = handover.player, paused != player?.bundleID { return false }
        return true
    }
}
