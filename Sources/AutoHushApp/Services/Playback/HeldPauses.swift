import Foundation
import AutoHushKit

/// A player's monitoring, as `HeldPauses` keeps it: a `MonitoringPipeline`
/// (see `SessionMonitoring`).
@MainActor
protocol HeldMonitoring: AnyObject {
    func stop()
    /// Stops; `handingOver`: the monitoring started for the same player
    /// object in its place has taken its pause over (see
    /// `MonitoringPipeline.stop(handingOver:)`).
    func stop(handingOver: Bool)
    /// Stops, and waits until a faded-down player has its volume back.
    func stopAndRestoreVolume() async
    /// Returns once no resume is under way, the music fading back in included.
    func waitForResume() async
    func setAutoPauseEnabled(_ enabled: Bool)
    func setIgnoredSources(_ ids: Set<String>)
    func setDetectionMethod(_ method: DetectionMethod)
    func setConfiguration(_ configuration: AppConfiguration)
    /// See `PlaybackArbiter.holdResumes`.
    func holdResumes(_ held: Bool)
    /// See `PlaybackArbiter.setKeptMuteShown`.
    func setKeptMuteShown(_ shown: Bool)
}

/// The monitoring of players AutoHush held paused when the user chose
/// another. Each runs on only to end its own pause, as it would have (the
/// other apps stop: its player plays again), and stops once its player is
/// anything but paused by it: played again (once faded back in), or taken
/// over by the user, or muted with its real pause refused and no app
/// playing: with no card to show that mute, it's unmuted (D2, the user's
/// pick, 2026-11-07). A player chosen again is taken back (`choose`,
/// `takesBack`), its monitoring parked until the new one has taken the
/// pause over (`handOver`); the Mac sleeping forgets them all (`stopAll`),
/// as any pause then (decision S2); quitting hands them over (`bundleIDs`,
/// `stopAndRestoreAll`).
@MainActor
final class HeldPauses {
    private struct Held {
        let token: UUID
        /// The player object it monitors.
        let player: any MusicPlayer
        let monitoring: any HeldMonitoring
        /// Started to take a handed-over pause over: what it reports before
        /// it has (the player's state as it found it) doesn't count.
        var awaitingTakeOver: Bool
        /// Its player is no longer paused by it: it stops once the resume
        /// under way is over (`end`).
        var isEnding = false
        /// Its player is muted in place of the pause by its monitoring's
        /// own tap, as it last said (`MonitoringStatusUpdate.mutedInstead`),
        /// and whether so while it said it doesn't play (its `whileQuiet`).
        var mutedInstead: Bool
        var mutedWhileQuiet: Bool

        var bundleID: String { player.bundleID }
    }

    /// The monitoring that held a pause taken back (its player chosen
    /// again, or the chosen one checked again or its permission lost),
    /// left running, its resumes held, until the next start has taken that
    /// pause over (`handOver`): the new hold exists before this one lets
    /// go, so a mute standing for the pause is never lifted between them
    /// (app-services-2, diff-app-1). With no start to take it, it stops as
    /// before (`endParked`).
    private struct Parked {
        let monitoring: any HeldMonitoring
        /// The player object it monitors.
        let player: any MusicPlayer
        let mutedInstead: Bool
        let mutedWhileQuiet: Bool
        /// Let go of once it's stopped (`MusicPlayer.release`): another
        /// object of its app took its place (checked again), and it turned
        /// something on in that app.
        let releasing: (any MusicPlayer)?

        init(_ monitoring: any HeldMonitoring, player: any MusicPlayer, mutedInstead: Bool, mutedWhileQuiet: Bool,
             chosen: any MusicPlayer) {
            self.monitoring = monitoring
            self.player = player
            self.mutedInstead = mutedInstead
            self.mutedWhileQuiet = mutedWhileQuiet
            releasing = player.releasesOnQuit && !PlayerSession.isSame(player, chosen) ? player : nil
        }
    }

    /// A take-back a start answers for (`takesBack`), until its `handOver`.
    struct TakeBack {
        fileprivate let id: UUID
        /// The player object whose monitoring held the pause, parked; `nil`
        /// when none runs any more (a start that failed stopped it), so
        /// only a real pause is left to take back.
        let heldBy: (any MusicPlayer)?
        /// That monitoring's tap muted the player in place of the pause,
        /// while it said it doesn't play when `mutedWhileQuiet`.
        let mutedInstead: Bool
        let mutedWhileQuiet: Bool
    }

    private var held: [Held] = []
    /// The player taken back, whose next monitoring takes its pause over.
    private var pendingTakeBack: String?
    /// The monitoring that held it, parked until a start takes it (`takesBack`).
    private var parked: Parked?
    /// Parked monitorings a start took, by its take-back, until its `handOver`.
    private var handingOver: [UUID: Parked] = [:]
    /// A player's held pause is over (not taken back): what it turned on
    /// in its app can go back off (`PlayerSession.releaseLeft`).
    var onEnded: @MainActor (String) -> Void = { _ in }

    /// None kept or parked, a pause still ending (its player fading back
    /// in) included.
    var isEmpty: Bool { held.isEmpty && parked == nil && handingOver.isEmpty }
    /// The players held paused: not those whose pause is ending.
    var bundleIDs: [String] { held.filter { !$0.isEnding }.map(\.bundleID) }

    /// The user chooses `chosen` while `current` (its updates come with
    /// `token`) monitors `leaving`, holding its player paused when
    /// `holdsPause` (muted in place of the pause by its tap when
    /// `mutedInstead`, while it said it doesn't play when
    /// `mutedWhileQuiet`): it's kept, and `true` says it must be left running.
    /// A player held paused that is chosen again is taken back, and so is
    /// the one held now when its app is chosen again (checked again: a new
    /// player) or its permission was lost (the same one): the monitoring
    /// that held the pause is parked, left running until the next start has
    /// taken it over (`handOver`), and `true` says so for the current one.
    func choose(_ chosen: any MusicPlayer, leaving: (any MusicPlayer)?, current: (any HeldMonitoring)?, token: UUID,
                holdsPause: Bool, mutedInstead: Bool = false, mutedWhileQuiet: Bool = false) -> Bool {
        let bundleID = chosen.bundleID
        var leftRunning = false
        if holdsPause, let current, let leaving, leaving.bundleID != bundleID {
            keep(current, token: token, player: leaving, mutedInstead: mutedInstead, mutedWhileQuiet: mutedWhileQuiet)
            leftRunning = true
        }
        if let index = held.firstIndex(where: { $0.bundleID == bundleID }) {
            let taken = held.remove(at: index)
            // Its pause ending already (it plays again): nothing to hand over.
            if taken.isEnding { taken.monitoring.stop() }
            takeBack(bundleID, parking: taken.isEnding ? nil
                : Parked(taken.monitoring, player: taken.player, mutedInstead: taken.mutedInstead,
                         mutedWhileQuiet: taken.mutedWhileQuiet, chosen: chosen))
        } else if holdsPause, let leaving, leaving.bundleID == bundleID {
            takeBack(bundleID, parking: current.map {
                Parked($0, player: leaving, mutedInstead: mutedInstead, mutedWhileQuiet: mutedWhileQuiet, chosen: chosen)
            })
            leftRunning = current != nil
        }
        return leftRunning
    }

    /// `bundleID`'s pause is taken back by its next start, `parking` the
    /// monitoring that held it till then, its resumes held: one parked for
    /// an earlier take-back that no start took stops, as before, unless
    /// it's this one's, taken back again with nothing new to park.
    private func takeBack(_ bundleID: String, parking: Parked?) {
        if pendingTakeBack == bundleID, parking == nil { return }
        endParked()
        pendingTakeBack = bundleID
        parking?.monitoring.holdResumes(true)
        parked = parking
    }

    /// Monitoring for `bundleID` starts: whether it takes a held pause back
    /// over (the player taken back last only), and what held it, for its
    /// `handOver` once it has started. Any start ends the wait, so a pause
    /// is never taken over for a player AutoHush didn't pause: another
    /// player's start stops what's parked, as before.
    func takesBack(_ bundleID: String) -> TakeBack? {
        defer { pendingTakeBack = nil }
        guard pendingTakeBack == bundleID else {
            endParked()
            return nil
        }
        let taken = parked
        parked = nil
        let takeBack = TakeBack(id: UUID(), heldBy: taken?.player, mutedInstead: taken?.mutedInstead ?? false,
                                mutedWhileQuiet: taken?.mutedWhileQuiet ?? false)
        if let taken { handingOver[takeBack.id] = taken }
        return takeBack
    }

    /// The start that took `takeBack` is over, `player`'s new monitoring
    /// running (the chosen one's, or kept here as another was chosen
    /// meanwhile): the one parked for it stops, handing the pause over when
    /// the new one took it over on the same player object (`tookOver`), so
    /// a mute of the player's own is that one's now; else as before, its
    /// mutes lifted. Stopped already (sleep, quit): nothing more.
    func handOver(_ takeBack: TakeBack, tookOver: Bool, to player: any MusicPlayer) {
        guard let parked = handingOver.removeValue(forKey: takeBack.id) else { return }
        stopParked(parked, handingOver: tookOver && PlayerSession.isSame(parked.player, player))
    }

    /// No start will take the pause back from the parked monitoring (its
    /// access check failed, no player is chosen any more): it stops, its
    /// mutes lifted, as before it was parked. A real pause is still taken
    /// back by the next start (`takesBack`).
    func endParked() {
        guard let parked else { return }
        self.parked = nil
        stopParked(parked)
    }

    private func stopParked(_ parked: Parked, handingOver: Bool = false) {
        parked.monitoring.stop(handingOver: handingOver)
        if let releasing = parked.releasing { Task { await releasing.release() } }
    }

    /// Whether `monitoring` is kept here, holding its player's pause.
    func keeps(_ monitoring: any HeldMonitoring) -> Bool {
        held.contains { $0.monitoring === monitoring }
    }

    /// `player` is let go of once its parked monitoring stops (`Parked.releasing`).
    func releasesOnceParkedStops(_ player: any MusicPlayer) -> Bool {
        allParked.contains { $0.releasing.map { PlayerSession.isSame($0, player) } ?? false }
    }

    private var allParked: [Parked] { [parked].compactMap { $0 } + handingOver.values }

    /// `monitoring` (its updates come with `token`) holds `player` paused
    /// (muted in place of the pause by its tap when `mutedInstead`, as
    /// `choose` says), or,
    /// `awaitingTakeOver`, starts to take a handed-over pause over: it runs
    /// on, a mute it would keep with no app playing lifted instead once
    /// none plays (not heard over them), since the menu shows only the
    /// chosen player's.
    func keep(_ monitoring: any HeldMonitoring, token: UUID, player: any MusicPlayer, awaitingTakeOver: Bool = false,
              mutedInstead: Bool = false, mutedWhileQuiet: Bool = false) {
        let bundleID = player.bundleID
        for replaced in held where replaced.bundleID == bundleID { replaced.monitoring.stop() }
        held.removeAll { $0.bundleID == bundleID }
        held.append(Held(token: token, player: player, monitoring: monitoring, awaitingTakeOver: awaitingTakeOver,
                         mutedInstead: mutedInstead, mutedWhileQuiet: mutedWhileQuiet))
        monitoring.setKeptMuteShown(false)
    }

    /// The monitoring with `token` found no pause to take over, or its pause
    /// is over: it stops, unless it was stopped already.
    func drop(_ token: UUID) {
        guard let index = held.firstIndex(where: { $0.token == token }) else { return }
        let ended = held.remove(at: index)
        ended.monitoring.stop()
        onEnded(ended.bundleID)
    }

    /// An update from the monitoring with `token`: `true` when it's one kept
    /// here and stays its own (the app applies the others). A kept one stops
    /// once its player is no longer paused by it. What AntiDot learned is
    /// the app's, whichever monitoring learned it.
    func takes(_ update: MonitoringStatusUpdate, from token: UUID) -> Bool {
        guard let index = held.firstIndex(where: { $0.token == token }) else { return false }
        if held[index].awaitingTakeOver, case .playback(let state) = update {
            if state == .pausedByMonitor { held[index].awaitingTakeOver = false }
            return true
        }
        switch update {
        case .playback(let state) where state != .pausedByMonitor && state != .unknown:
            end(index)
            return true
        case .mutedInstead(let muted, let whileQuiet):
            held[index].mutedInstead = muted
            held[index].mutedWhileQuiet = whileQuiet
            return true
        case .learnedAssertions:
            return false
        default:
            return true
        }
    }

    /// The monitoring at `index` no longer pauses its player: it stops once
    /// the player has faded back in, since stopping cuts a fade short (the
    /// user's volume back at once). It's kept meanwhile, so choosing the
    /// player again, sleep or quitting still stops it at once. It pauses
    /// nothing any more: an app starting during the fade-in would have it
    /// pause a player that isn't chosen, then stop with that pause held.
    private func end(_ index: Int) {
        guard !held[index].isEnding else { return }
        held[index].isEnding = true
        let (token, monitoring) = (held[index].token, held[index].monitoring)
        monitoring.setAutoPauseEnabled(false)
        Task { [weak self] in
            await monitoring.waitForResume()
            self?.drop(token)
        }
    }

    /// The settings a held pause follows, as the chosen player's monitoring
    /// does: Auto-Pause off, or the playing app ignored, ends it at once. One
    /// whose pause is ending keeps Auto-Pause off (`end`). The detection
    /// method too, so AntiDot mode leaves no audio taps behind (a parked
    /// one's included). And the timings and switches (Resume playback, Stay
    /// paused after calls, Pause for VoiceOver, the fades), so a held pause
    /// ends as the user set meanwhile (K1-7, 2026-11-06).
    func setAutoPauseEnabled(_ enabled: Bool) {
        held.filter { !$0.isEnding }.forEach { $0.monitoring.setAutoPauseEnabled(enabled) }
    }
    func setIgnoredSources(_ ids: Set<String>) { held.forEach { $0.monitoring.setIgnoredSources(ids) } }
    func setDetectionMethod(_ method: DetectionMethod) {
        held.forEach { $0.monitoring.setDetectionMethod(method) }
        allParked.forEach { $0.monitoring.setDetectionMethod(method) }
    }
    /// `configuration`, each for its own player, whose audio never counts as
    /// another app playing.
    func setConfiguration(_ configuration: AppConfiguration) {
        for each in held {
            var own = configuration
            own.musicPlayerBundleID = each.bundleID
            each.monitoring.setConfiguration(own)
        }
    }
    /// Held, each keeps its player paused, as the chosen player's
    /// monitoring does (`PlayerSession.holdResumes`). A parked one's stay
    /// held until it stops.
    func holdResumes(_ held: Bool) { self.held.forEach { $0.monitoring.holdResumes(held) } }

    /// The parked ones too, their mutes lifted, as before they were parked.
    func stopAll() {
        let ended = held
        let parked = allParked
        held = []
        pendingTakeBack = nil
        self.parked = nil
        handingOver = [:]
        for each in parked { stopParked(each) }
        for each in ended {
            each.monitoring.stop()
            onEnded(each.bundleID)
        }
    }

    /// AutoHush quits: each stops, its player's volume back first (one
    /// fading in, say); a parked one lets go of its player too.
    func stopAndRestoreAll() async {
        let stopping = held
        let parked = allParked
        held = []
        pendingTakeBack = nil
        self.parked = nil
        handingOver = [:]
        for each in stopping { await each.monitoring.stopAndRestoreVolume() }
        for each in parked {
            await each.monitoring.stopAndRestoreVolume()
            await each.releasing?.release()
        }
    }
}
