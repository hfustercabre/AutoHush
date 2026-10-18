import Foundation

// PlaybackArbiter: pausing the music, and when.
extension PlaybackArbiter {
    /// Pauses the music in a task of its own, unless a pause is already
    /// under way: that one sees the new sources too.
    func startPause() {
        guard pauseTask == nil else { return }
        pauseTask = Task {
            await pauseMusicIfNeeded()
            pauseTask = nil
            publishPlaybackState()
        }
    }

    /// Pauses after `delay` if other apps are still playing then. A newer
    /// pause, an app starting or auto-pause going off calls it off.
    func schedulePause(after delay: TimeInterval) {
        cancelPendingPause()
        let id = UUID()
        pendingPauseID = id
        let wait = debounceScheduler.scheduleDebounce(after: delay)
        pendingPauseWait = wait
        pendingPauseTask = Task { [weak self] in
            _ = await wait.value
            await self?.pauseIfStillPending(id: id)
        }
    }

    private func pauseIfStillPending(id: UUID) {
        guard pendingPauseID == id else { return }
        pendingPauseTask = nil
        pendingPauseWait = nil
        pendingPauseID = nil
        if !activeSources.isEmpty { startPause() }
    }

    func cancelPendingPause() {
        pendingPauseTask?.cancel()
        pendingPauseTask = nil
        pendingPauseWait = nil
        pendingPauseID = nil
    }

    private func pauseMusicIfNeeded() async {
        guard autoPauseEnabled, !isAsleep else { return }
        let checked = clock()
        guard playsLocally else {
            // A player paused here closes its output a few seconds later,
            // maybe before the app that paused it counts as playing.
            if mayBeStartingAppsPause(checkedAt: checked),
               takeOverPauseOfStartingApp(await livePlayerState(), checkedAt: checked) {
                return
            }
            logger.info("[arbiter] \(self.player.name, privacy: .public) isn’t playing on this Mac — not pausing")
            return
        }
        let state = await livePlayerState()
        guard state == .playing else {
            if await muteIfPlayingAnyway(saying: state) { return }
            if takeOverPauseOfStartingApp(state, checkedAt: checked) { return }
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) — not pausing")
            return
        }
        // Found playing: a pause from now on (the user's, during the fade-out)
        // is no app's doing.
        latestStart = nil
        // Things may have changed while the player answered.
        guard !isShutDown, autoPauseEnabled, !isFadingOut, !activeSources.isEmpty else { return }
        isFadingOut = true
        noteCalls()
        if let levelLowered { volumeLeveler?.restore(over: configuration.fadeOutDuration, lowered: levelLowered) } // as the music fades out
        levelLowered = nil
        let paused: Bool
        do {
            paused = try await fader.fadeOutAndPause()
        } catch MusicPlayerError.stillLearning {
            isFadingOut = false
            logger.info("[arbiter] \(self.player.name, privacy: .public)’s controls aren’t learned yet — not pausing")
            return
        } catch {
            isFadingOut = false
            logger.error("[arbiter] pausing \(self.player.name, privacy: .public) failed: \(error)")
            // Unless every app stopped meanwhile: then there's nothing to say.
            if !activeSources.isEmpty, autoPauseEnabled, !isAsleep {
                pauseFailure = error as? MusicPlayerError ?? .playerCommandFailed(.pressFailed)
            }
            return
        }
        isFadingOut = false
        if paused { pauseFailure = nil }
        guard paused else {
            logger.info("[arbiter] pause called off during the fade-out (playing now: \(self.playingApps, privacy: .public))")
            // Another app may have started while the music came back up.
            if !activeSources.isEmpty, !isShutDown { await pauseMusicIfNeeded() }
            return
        }
        playerState = .paused
        logger.info("[arbiter] \(self.player.name, privacy: .public) paused, because these apps play: \(self.playingApps, privacy: .public)")
        guard holdPause() else { return }
        if !autoPauseEnabled {
            // Auto-pause was turned off while we were pausing: undo it.
            scheduleResume(after: nil)
        } else if activeSources.isEmpty, !isShutDown {
            // Every app stopped while we were pausing, too late to call it off.
            scheduleResume(after: nil)
        }
    }

    /// A player that says it's paused or stopped while it plays here (a web
    /// app's ad, during which its button reads "Play") is muted instead, if it
    /// can be: that's our pause, and resuming lifts the mute.
    private func muteIfPlayingAnyway(saying state: PlayerState) async -> Bool {
        guard state == .paused || state == .stopped, let muting = player as? any MutingMusicPlayer,
              await muting.muteIfPlayingAnyway() else { return false }
        pauseFailure = nil
        playerState = .paused
        logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) but can be heard — muted, because these apps play: \(self.playingApps, privacy: .public)")
        // Things may have changed while it was measured.
        if holdPause(), !isShutDown, !autoPauseEnabled || activeSources.isEmpty { scheduleResume(after: nil) }
        return true
    }

    /// The player was found paused by the check an app's start called for,
    /// having stopped playing as that app started: the app paused it (VLC
    /// does, by default, with Spotify and Music). That pause counts as ours,
    /// so the music comes back once the apps stop, as if AutoHush had paused
    /// it. A pause from before the app was heard, or more than
    /// `startPauseWindow` after, is the user's, and stays.
    func takeOverPauseOfStartingApp(_ state: PlayerState, checkedAt checked: Date) -> Bool {
        guard state == .paused, !isShutDown, autoPauseEnabled, mayBeStartingAppsPause(checkedAt: checked) else {
            return false
        }
        pauseFailure = nil
        logger.info("[arbiter] \(self.player.name, privacy: .public) stopped as another app started — it comes back once the apps stop (playing now: \(self.playingApps, privacy: .public))")
        // Things may have changed while the player answered.
        if holdPause(), !isShutDown, activeSources.isEmpty { scheduleResume(after: nil) }
        return true
    }

    /// Whether, by timing alone, the player's stop could be the doing of the
    /// latest app to start, in a check `checked` at most `startCheckWindow`
    /// after it counted as playing: the stop came surely after the app was
    /// first heard (give or take `hearingDelay`) and at most
    /// `startPauseWindow` after. Its report may come late
    /// (`MusicPlayer.stateReportDelay`), so a stop reported by a player read
    /// once a second can't be placed that precisely, and never counts.
    private func mayBeStartingAppsPause(checkedAt checked: Date) -> Bool {
        guard !pausedByUs, let start = latestStart, let stopped = stoppedPlayingAt,
              checked.timeIntervalSince(start.counted) <= Self.startCheckWindow else { return false }
        let earliest = stopped.addingTimeInterval(-player.stateReportDelay)
        return earliest.timeIntervalSince(start.heard) >= -Self.hearingDelay
            && stopped.timeIntervalSince(start.heard) <= Self.startPauseWindow
    }

    /// The music is paused, or muted, by us now. When the Mac went to sleep
    /// while that was under way (the fade-out or the listening took that
    /// long), the pause is forgotten at once, as any pause held then (see
    /// `setAsleep`): `false`.
    private func holdPause() -> Bool {
        guard isAsleep else {
            pausedByUs = true
            return true
        }
        forgotPauseInSleep = true
        logger.info("[arbiter] paused as the Mac went to sleep: \(self.player.name, privacy: .public) stays paused")
        return false
    }
}
