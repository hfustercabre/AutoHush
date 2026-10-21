import Foundation

// PlaybackArbiter: resuming it, and when.
extension PlaybackArbiter {
    /// Calls off the pending resume: a source started, Auto-Pause went off,
    /// the Mac sleeps, resumes are held, or the arbiter shuts down.
    func cancelPendingResume() {
        if pendingResumeID != nil { putBackResumeLevel() } // it won't bring the music back
        forgetPendingResume()
    }

    /// Forgets the pending resume, for a newer one to take its place.
    private func forgetPendingResume() {
        if let pendingResumeID, let pendingResumeTask { calledOff[pendingResumeID] = (pendingResumeTask, pendingResumeWait) }
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        pendingResumeWait = nil
        pendingResumeID = nil
    }

    /// The resume that lowered the Mac's volume (Level the volume) ended
    /// without the music playing: the volume is put back at once, not left
    /// lowered for music that doesn't play.
    func putBackResumeLevel() {
        guard resumeLowered else { return }
        resumeLowered = false
        if let levelLowered { volumeLeveler?.restoreNow(lowered: levelLowered) }
        levelLowered = nil
    }

    /// Resumes the music in a task of its own: after `delay`, or right away
    /// when it is `nil`. A newer resume or a source starting calls it off.
    func scheduleResume(after delay: TimeInterval?, retriesLeft: Int = PlaybackArbiter.resumeRetries) {
        forgetPendingResume()
        let id = UUID()
        pendingResumeID = id
        let debounceTask = delay.map { debounceScheduler.scheduleDebounce(after: $0) }
        pendingResumeWait = debounceTask
        pendingResumeTask = Task { [weak self] in
            _ = await debounceTask?.value
            await self?.resumeIfStillPending(id: id, retriesLeft: retriesLeft)
        }
    }

    private func resumeIfStillPending(id: UUID, retriesLeft: Int) async {
        defer { pendingTaskEnded(id) }
        if takenOver?.resume == id { takenOver = nil } // its wait is over
        guard pendingResumeID == id, !isShutDown, !isAsleep else { return }
        // With auto-pause off, music we paused comes back even while others play.
        guard activeSources.isEmpty || !autoPauseEnabled else {
            putBackResumeLevel()
            return
        }
        guard pausedByUs else {
            putBackResumeLevel()
            publishPlaybackState()
            return
        }
        guard !resumesHeld else {
            logger.info("[arbiter] \(self.player.name, privacy: .public) stays paused until Add an App’s check ends")
            putBackResumeLevel()
            publishPlaybackState()
            return
        }
        guard configuration.resumesPlayback else {
            logger.info("[arbiter] \(self.player.name, privacy: .public) stays paused: Resume playback is off")
            await keepPaused()
            return
        }
        guard !(configuration.staysPausedAfterCalls && callDuringPause) else {
            logger.info("[arbiter] \(self.player.name, privacy: .public) stays paused: a call came during the pause (Stay paused after calls)")
            await keepPaused()
            return
        }
        await resumeNow(id: id, retriesLeft: retriesLeft)
    }

    /// Our pause, kept instead of resumed (or as the output went away),
    /// becomes the user's.
    func keepPaused() async {
        pausedByUs = false
        putBackResumeLevel()
        // A mute standing in for the pause: the player is paused for real
        // and the mute lifted, as when the Mac slept (`forgetPause`).
        if let muting = player as? any MutingMusicPlayer { await muting.forgetPause() }
        publishPlaybackState()
    }

    /// Resumes the player after re-checking its live state: if the user manually
    /// paused, resumed, or quit it while the source was active, respect
    /// that and do not override their intent. Gives up when the pending
    /// resume `id` was cancelled or replaced while the player was queried.
    private func resumeNow(id: UUID, retriesLeft: Int) async {
        let currentState = await livePlayerState()
        guard !isShutDown, pendingResumeID == id else { return }
        if currentState == .unknown, retriesLeft > 0 {
            logger.info("[arbiter] \(self.player.name, privacy: .public) didn’t answer — trying the resume again")
            scheduleResume(after: Self.resumeRetryDelay, retriesLeft: retriesLeft - 1)
            return
        }
        guard currentState == .paused else {
            logger.info("[arbiter] resume skipped — \(self.player.name, privacy: .public) is \(currentState.rawValue, privacy: .public) (user interaction detected)")
            pausedByUs = false
            // Playing (an earlier try's play went through, or the user's), it
            // plays at the volume lowered for it, put back at its next pause.
            if currentState == .playing { resumeLowered = false } else { putBackResumeLevel() }
            publishPlaybackState()
            return
        }

        // After quieter apps, the Mac's volume lowered to their level first,
        // while nothing plays (Settings → Behavior). A try again finds it
        // lowered already, by the try before.
        if configuration.levelsMusic, let volumeLeveler, let offset = await resumeOffset() {
            guard !isShutDown, pendingResumeID == id else { return }
            if let token = volumeLeveler.lower(by: offset) { levelLowered = token }
            if levelLowered != nil { resumeLowered = true }
        }

        // Forget the pending resume without cancelling it: this may be running
        // inside it, and a cancelled task would rush the fade-in's steps.
        let resuming = pendingResumeTask
        resumeTask = resuming
        pendingResumeTask = nil
        pendingResumeWait = nil
        pendingResumeID = nil
        pausedByUs = false
        do {
            try await fader.playAndFadeIn()
            playerState = .playing
            resumeLowered = false // the music plays at the volume lowered for it
            logger.info("[arbiter] \(self.player.name, privacy: .public) resumed, because \(self.autoPauseEnabled ? "no other app plays" : "Auto-Pause is off", privacy: .public)")
        } catch {
            logger.error("[arbiter] resume failed: \(error)")
            // Still ours to resume, unless something called it off meanwhile.
            if retriesLeft > 0, !isShutDown, !isAsleep, pendingResumeID == nil,
               activeSources.isEmpty || !autoPauseEnabled {
                pausedByUs = true
                scheduleResume(after: Self.resumeRetryDelay, retriesLeft: retriesLeft - 1)
            } else {
                putBackResumeLevel() // given up
            }
        }
        publishPlaybackState()
        if resumeTask == resuming { resumeTask = nil } // unless a newer resume started meanwhile
    }
}
