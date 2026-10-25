import Foundation
import AutoHushKit

// PlayerSession: what the app tells it.
extension PlayerSession {
    /// At launch, once the copies of AutoHush opened before this one have
    /// quit: the players they held paused get their monitoring again, then
    /// the chosen player starts.
    func launch(now: Date = Date()) {
        startHeldPauses(handedOverHeldPlayers(now: now))
        if player != nil { requestStart() }
    }

    /// The user chose `newPlayer`: a pause AutoHush holds on the player it
    /// leaves is still its own to end, so that player's monitoring runs on
    /// for it (`heldPauses`), and a player held paused that is chosen again
    /// is taken back by its new monitoring. `nil`: no player is chosen any
    /// more (it was deleted), and nothing runs.
    func choose(_ newPlayer: any MusicPlayer?) {
        guard let newPlayer else {
            player = nil
            startGeneration += 1 // a start under way gives up
            cancelRetry()
            tearDownMonitoring()
            setHealth(nil)
            return
        }
        let leaving = player
        holdPause(for: newPlayer.bundleID)
        player = newPlayer
        if let leaving { releaseLeft(leaving) }
        failedStarts = 0
        setHealth(.starting)
        requestStart()
    }

    /// A player no longer chosen turns back off what it turned on in its app
    /// (an Electron or Chromium app's switch for assistive tools, a mute),
    /// once AutoHush holds no pause of it: at once, or when its held pause
    /// is over (`HeldPauses.onEnded`). Chosen again meanwhile, it keeps them.
    /// The same player object (any player AutoHush has is an actor or a
    /// class); a value is the same by its app.
    static func isSame(_ player: any MusicPlayer, _ other: any MusicPlayer?) -> Bool {
        guard let other else { return false }
        guard type(of: player as Any) is AnyClass, type(of: other as Any) is AnyClass else {
            return player.bundleID == other.bundleID
        }
        return (player as AnyObject) === (other as AnyObject)
    }

    func releaseLeft(_ leaving: any MusicPlayer) {
        // The same app chosen again (checked again: a new player) releases its old one.
        guard leaving.releasesOnQuit, !Self.isSame(leaving, player) else { return }
        if heldPauses.bundleIDs.contains(leaving.bundleID) {
            leftPlayers[leaving.bundleID] = leaving
            return
        }
        leftPlayers[leaving.bundleID] = nil
        logger.info("\(leaving.name, privacy: .public) is no longer the media player: what it turned on goes back off")
        Task { await leaving.release() }
    }

    /// Starts over at once, with the waits between automatic tries back to
    /// the shortest: Try Again on the menu's card, or the player installed again.
    func retry() {
        failedStarts = 0
        setHealth(.starting)
        requestStart()
    }

    /// An app opened: the chosen player is controlled afresh; it may not
    /// answer yet while it finishes starting up.
    func playerLaunched(_ bundleID: String) {
        guard let player, bundleID == player.bundleID else { return }
        logger.debug("\(player.name, privacy: .public) launch detected — starting again")
        failedStarts = 0
        setHealth(.starting)
        requestStart(retries: Self.startupRetries)
    }

    /// Whether the chosen player is installed, as AutoHush last found: once
    /// it's gone, nothing runs and the health says so; once it's back, it's
    /// controlled afresh.
    func setPlayerInstalled(_ installed: Bool) {
        guard let player else { return }
        let notInstalled = AppHealthState.playerNotInstalled(player.name)
        if installed {
            if state.health == notInstalled { retry() }
        } else if state.health != notInstalled {
            logger.notice("\(player.name, privacy: .public) isn’t installed")
            startGeneration += 1 // a start under way gives up
            cancelRetry()        // and none is tried until it's back
            tearDownMonitoring()
            setHealth(notInstalled)
        }
    }

    /// Checks again that AutoHush may still control the player, when it
    /// matters: another app starts playing, or the menu opens. macOS doesn't
    /// announce a permission taken away while monitoring runs, and the player
    /// then only reads as unknown, so nothing would be paused, silently. A
    /// missing permission starts over as at launch: the menu asks for it, and
    /// monitoring starts again by itself once it's given back.
    func checkAccess() {
        guard state.health == .ready, let player, accessCheck == nil else { return }
        let generation = startGeneration
        accessCheck = Task { [weak self] in
            defer { self?.accessCheck = nil }
            do {
                try await player.verifyControlAccess()
            } catch {
                guard let self, generation == self.startGeneration else { return }
                switch error as? MusicPlayerError {
                case .automationPermissionDenied?, .accessibilityPermissionDenied?:
                    self.logger.error("Lost control of \(player.name, privacy: .public): \(error)")
                    self.requestStart()
                default:
                    break // the player quit or didn't answer: monitoring follows those
                }
            }
        }
    }

    /// Music AutoHush paused stays paused after the Mac sleeps: the
    /// arbiter forgets the pause as the Mac falls asleep, when the other
    /// apps' sound stops too, and decides nothing until it's awake.
    func setAsleep(_ asleep: Bool) {
        guard asleep != isAsleep else { return }
        isAsleep = asleep
        // As any pause: after sleeping it's the user's (decision S2).
        if asleep { heldPauses.stopAll() }
        logger.info("The Mac \(asleep ? "goes to sleep" : "woke up", privacy: .public)")
        monitoring?.setAsleep(asleep)
    }

    /// Try Again on the menu's "Couldn't resume": the resume once more.
    func retryResume() {
        guard !hasQuit else { return }
        monitoring?.retryResume()
    }

    /// Listens to the chosen player as the menu opens, so the menu says at
    /// once whether it plays silently (the user, 2026-10-24).
    func checkPlayerHeard() {
        guard !hasQuit else { return }
        monitoring?.checkPlayerHeard()
    }

    /// Holds every resume, or lets them happen again: the chosen player's,
    /// the held pauses', and those of a monitoring started meanwhile, which
    /// starts held. While held, a player AutoHush paused stays paused, and
    /// one that plays is still paused when another app starts; released, the
    /// music comes back as usual (see `PlaybackArbiter.holdResumes`).
    /// Quitting ends the hold: the pauses are handed over as any (`quit`),
    /// and the AutoHush opened next resumes them once no other app plays.
    func holdResumes(_ held: Bool) {
        guard !hasQuit, held != resumesHeld else { return }
        resumesHeld = held
        monitoring?.holdResumes(held)
        heldPauses.holdResumes(held)
    }

    /// AutoHush quits: the pauses it holds are handed over, so an AutoHush
    /// opened next (an update, another copy, a quick reopen) resumes the
    /// music once the other apps stop. Later than `pauseHandoverMaxAge`,
    /// it's ignored, and so is one for another player than the one chosen by
    /// then. Every monitoring then stops, a faded-down player getting its
    /// volume back first: the task returned ends once that's done; `nil`
    /// when nothing runs. Nothing starts from then on, and a start under way
    /// gives up: a monitoring it made would run on with nothing to stop it.
    func quit(now: Date = Date()) -> Task<Void, Never>? {
        hasQuit = true
        startGeneration += 1
        cancelRetry()
        handOverPauses(now: now)
        let monitoring = self.monitoring
        let player = player
        // Those left with a pause held, which they then end with AutoHush.
        let left = Array(leftPlayers.values)
        leftPlayers = [:]
        guard monitoring != nil || !heldPauses.isEmpty else {
            let releasing = ([player].compactMap { $0 } + left).filter(\.releasesOnQuit)
            guard !releasing.isEmpty else { return nil }
            return Task { for each in releasing { await each.release() } }
        }
        self.monitoring = nil
        let heldPauses = heldPauses
        return Task {
            await monitoring?.stopAndRestoreVolume()
            await heldPauses.stopAndRestoreAll()
            await player?.release()
            for each in left { await each.release() }
        }
    }

    /// AutoHush holds a pause, the chosen player's or a held one.
    var isHoldingPause: Bool {
        state.playback == .pausedByMonitor || !heldPauses.isEmpty
    }

    /// The apps with sound as the monitoring sees them, for Diagnostics.
    func activeAudioReport() -> [ActiveAudioReport.Entry] {
        monitoring?.activeAudioReport() ?? []
    }
}
