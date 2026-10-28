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
            // No pause came of it (the fade-out called off, the pause failed,
            // the player still learning): a call during its fade-out is forgotten.
            if !pausedByUs { callDuringPause = false }
            outputGoneDuringPause = false
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
        defer { pendingTaskEnded(id) }
        guard pendingPauseID == id else { return }
        pendingPauseTask = nil
        pendingPauseWait = nil
        pendingPauseID = nil
        if !activeSources.isEmpty { startPause() }
    }

    func cancelPendingPause() {
        if let pendingPauseID, let pendingPauseTask { calledOff[pendingPauseID] = (pendingPauseTask, pendingPauseWait) }
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
            if state != .notRunning, await mutesHeardWhileQuiet(state) { return }
            logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) — not pausing")
            return
        }
        // Found playing: a pause from now on (the user's, during the fade-out)
        // is no app's doing.
        latestStart = nil
        heardWhileQuietSince = nil
        // Things may have changed while the player answered.
        guard !isShutDown, autoPauseEnabled, !isFadingOut, !activeSources.isEmpty else { return }
        // Not heard (a muted trailer, a silent preview): nothing to pause.
        // Read from the levels the monitor measures, so nothing waits; asked
        // again every second while apps play, so it's paused once heard.
        let hearing = await hearsPlayer(nil)
        if case .measuring(let remaining) = hearing {
            // Its tap was made with the other app's: not heard yet, but not
            // long enough to tell. A sound meanwhile tells at once.
            schedulePause(after: min(remaining, Self.silentRecheckInterval))
            return
        }
        // Unknown once the other app's output closes (nothing is measured
        // then): what was silent stays so, with nothing left to pause for.
        if hearing == .silent || (hearing == .unknown && playsSilently) {
            guard !isShutDown, autoPauseEnabled, !activeSources.isEmpty else { return }
            if !playsSilently {
                logger.info("[arbiter] \(self.player.name, privacy: .public) says it plays but isn’t heard — not pausing")
                // Only its open output said so: shown as not playing.
                silentWithoutState = !(await player.statesItself())
                guard !isShutDown, autoPauseEnabled, !activeSources.isEmpty else { return }
            }
            playsSilently = true // shown once this pause ends (`startPause`)
            schedulePause(after: Self.silentRecheckInterval)
            return
        }
        playsSilently = false
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
            guard !activeSources.isEmpty, autoPauseEnabled, !isAsleep, !isShutDown else { return }
            // The user's rule (2026-10-24): "If pauses didn't work, you should mute it".
            _ = await muteInsteadOfPause("refused to pause", failure: error as? MusicPlayerError ?? .playerCommandFailed(.pressFailed))
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
        pausedAt = clock()
        hearingDuringPause = nil
        leftToUser = false
        logger.info("[arbiter] \(self.player.name, privacy: .public) paused, because these apps play: \(self.playingApps, privacy: .public)")
        guard holdPause() else { return }
        if !autoPauseEnabled {
            // Auto-pause was turned off while we were pausing: undo it.
            scheduleResume(after: nil)
        } else if activeSources.isEmpty, !isShutDown {
            // Every app stopped while we were pausing, too late to call it off.
            scheduleResume(after: nil)
        } else if await hearsPlayer(nil) != .unknown, !(await pauseIsItsOwnMute()), pausedByUs, !isShutDown,
                  !activeSources.isEmpty {
            // Watched where its sound is measured (not in AntiDot mode), unless
            // its pause is a mute of its own.
            watchRestart(after: Self.restartWatchDelay)
        }
    }

    /// A player that says it's paused or stopped while it plays here (a web
    /// app's ad, during which its button reads "Play") is muted instead, if it
    /// can be: that's our pause, and resuming lifts the mute.
    private func muteIfPlayingAnyway(saying state: PlayerState) async -> Bool {
        guard state == .paused || state == .stopped, let muting = player as? any MutingMusicPlayer,
              await muting.muteIfPlayingAnyway() else { return false }
        // Its monitoring stopped while it was measured: a pause would be kept
        // (the user plays it again), but a mute nothing will ever lift is
        // lifted now (the user, 2026-10-20).
        guard !isShutDown else {
            await muting.releaseMute()
            return true
        }
        heldByMute = true
        pauseFailure = nil
        playerState = .paused
        logger.info("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) but can be heard — muted, because these apps play: \(self.playingApps, privacy: .public)")
        // Things may have changed while it was measured.
        if holdPause(), !isShutDown, !autoPauseEnabled || activeSources.isEmpty { scheduleResume(after: nil) }
        return true
    }

    /// A player heard while it says it's paused or stopped, as other apps
    /// play, is muted in place of a pause (the user, 2026-10-24: "If the
    /// selected player is producing sound … first you should try to pause it.
    /// If pauses didn't work, you should mute it"; its pause is pressed again
    /// while it's muted). Heard just now, it's looked at again a moment
    /// later, past a pause's tail, so a pause of the user's just before isn't
    /// taken for sound.
    private func mutesHeardWhileQuiet(_ state: PlayerState) async -> Bool {
        if let since = heardWhileQuietSince {
            heardWhileQuietSince = nil
            guard await hearsPlayer(since.addingTimeInterval(Self.pauseTail)) == .heard,
                  !isShutDown, autoPauseEnabled, !isFadingOut, !activeSources.isEmpty else { return false }
            let handled = await muteInsteadOfPause("is heard while it says it’s \(state.rawValue)",
                                                   failure: .playerCommandFailed(.pressIgnored))
            if pausedByUs, mutedInstead { mute.whileQuiet = true }
            return handled
        }
        guard await hearsPlayer(nil) == .heard, !isShutDown, autoPauseEnabled, !activeSources.isEmpty else { return false }
        heardWhileQuietSince = clock()
        schedulePause(after: Self.silentRecheckInterval)
        return true
    }

    /// The player was found paused by the check an app's start called for,
    /// having stopped playing as that app started: the app paused it (some
    /// players pause others by default as they start). That pause counts as
    /// ours, so the music comes back once the apps stop, as if AutoHush had
    /// paused it. A pause from before the app was heard, or more than
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
        if outputGoneDuringPause {
            outputGoneDuringPause = false
            logger.info("[arbiter] paused as the output went away: \(self.player.name, privacy: .public) stays paused")
            return false
        }
        guard isAsleep else {
            pausedByUs = true
            // A call already playing counts too: a pause taken over, or a
            // mute, has no fade-out that noted it.
            noteCalls()
            return true
        }
        forgotPauseInSleep = true
        logger.info("[arbiter] paused as the Mac went to sleep: \(self.player.name, privacy: .public) stays paused")
        return false
    }
}
