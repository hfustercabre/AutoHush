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
    func choose(_ newPlayer: (any MusicPlayer)?) {
        guard let newPlayer else {
            player = nil
            startGeneration += 1 // a start under way gives up
            cancelRetry()
            tearDownMonitoring()
            setHealth(nil)
            return
        }
        holdPause(for: newPlayer.bundleID)
        player = newPlayer
        failedStarts = 0
        setHealth(.starting)
        requestStart()
    }

    /// Starts over at once, with the waits between automatic tries back to
    /// the shortest: Retry on the menu's card, or the player installed again.
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
            logger.notice("\(player.name, privacy: .public) is not installed")
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
        guard monitoring != nil || !heldPauses.isEmpty else {
            guard let player, player.releasesOnQuit else { return nil }
            return Task { await player.release() }
        }
        self.monitoring = nil
        let heldPauses = heldPauses
        return Task {
            await monitoring?.stopAndRestoreVolume()
            await heldPauses.stopAndRestoreAll()
            await player?.release()
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
