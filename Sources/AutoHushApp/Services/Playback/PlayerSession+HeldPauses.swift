import Foundation
import AutoHushKit

// PlayerSession: held pauses and the hand-over.
extension PlayerSession {
    /// The user chooses `chosen`, or it's started again (`checkAccess`):
    /// see `choose(_:)`.
    func holdPause(for chosen: any MusicPlayer) {
        if heldPauses.choose(chosen, leaving: player, current: monitoring, token: monitoringToken,
                             holdsPause: state.playback == .pausedByMonitor, mutedInstead: state.mutedInstead,
                             mutedWhileQuiet: state.mutedWhileQuiet) {
            monitoring = nil // left running by the next start
        }
    }

    /// How the pause `takeBack` takes back was muted, for `player`'s new
    /// monitoring to mute it again the same way if it finds it playing
    /// (`MonitoringPipeline.start`): by AutoHush's tap (whatever it says,
    /// made while it said it doesn't play), or, held through
    /// another object of the app (checked again), by that one's own mute (an
    /// app added as Mute It Instead, a page's), while it still mutes it: an
    /// app only ever muted that the user played meanwhile is theirs (R6 of
    /// 11-27; it reads as playing then, its mute lifted). The same object
    /// still mutes itself, and reads as paused.
    func mutedBefore(_ takeBack: HeldPauses.TakeBack, for player: any MusicPlayer) async -> TakenBackMute? {
        if takeBack.mutedInstead { return .byTap(whileQuiet: takeBack.mutedWhileQuiet) }
        guard let old = takeBack.heldBy, !Self.isSame(old, player) else { return nil }
        if old.pausesByMuting { return await old.playerState() == .paused ? .byPlayer : nil }
        return await (old as? any MutingMusicPlayer)?.isMutedForPause() == true ? .byPlayer : nil
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
    /// What they turn on in their app goes back off once it's over, as for a
    /// player left with its pause held (`releaseLeft`).
    func startHeldPauses(_ bundleIDs: [String]) {
        for bundleID in bundleIDs {
            guard let held = players.player(bundleID: bundleID) else { continue }
            if held.releasesOnQuit { leftPlayers[bundleID] = held }
            let token = UUID()
            let monitoring = makeMonitoring(for: held, token: token)
            heldPauses.keep(monitoring, token: token, player: held, awaitingTakeOver: true)
            Task { [weak self, isAsleep] in
                // Played or quit by the user meanwhile: nothing to end.
                if await !monitoring.start(takingOverPause: true, mutedBefore: nil, asleep: isAsleep) { self?.heldPauses.drop(token) }
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
