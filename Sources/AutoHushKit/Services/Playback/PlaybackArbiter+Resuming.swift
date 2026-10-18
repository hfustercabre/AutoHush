import Foundation

// PlaybackArbiter: resuming it, and when.
extension PlaybackArbiter {
    func cancelPendingResume() {
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        pendingResumeWait = nil
        pendingResumeID = nil
    }

    /// Resumes the music in a task of its own: after `delay`, or right away
    /// when it is `nil`. A newer resume or a source starting calls it off.
    func scheduleResume(after delay: TimeInterval?, retriesLeft: Int = PlaybackArbiter.resumeRetries) {
        cancelPendingResume()
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
        if takenOver?.resume == id { takenOver = nil } // its wait is over
        guard pendingResumeID == id, !isShutDown, !isAsleep else { return }
        // With auto-pause off, music we paused comes back even while others play.
        guard activeSources.isEmpty || !autoPauseEnabled else { return }
        guard pausedByUs else {
            publishPlaybackState()
            return
        }
        guard !resumesHeld else {
            logger.info("[arbiter] \(self.player.name, privacy: .public) stays paused until Add an App’s check ends")
            publishPlaybackState()
            return
        }
        guard !(configuration.staysPausedAfterCalls && callDuringPause) else {
            logger.info("[arbiter] \(self.player.name, privacy: .public) stays paused: a call came during the pause (Stay paused after calls)")
            pausedByUs = false
            publishPlaybackState()
            return
        }
        await resumeNow(id: id, retriesLeft: retriesLeft)
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
            publishPlaybackState()
            return
        }

        // After quieter apps, the Mac's volume lowered to their level first,
        // while nothing plays (Settings → Advanced).
        if configuration.levelsMusic, let volumeLeveler, let offset = await resumeOffset() {
            guard !isShutDown, pendingResumeID == id else { return }
            volumeLeveler.lower(by: offset)
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
            logger.info("[arbiter] \(self.player.name, privacy: .public) resumed, because \(self.autoPauseEnabled ? "no other app plays" : "Auto-Pause is off", privacy: .public)")
        } catch {
            logger.error("[arbiter] resume failed: \(error)")
            // Still ours to resume, unless something called it off meanwhile.
            if retriesLeft > 0, !isShutDown, !isAsleep, pendingResumeID == nil,
               activeSources.isEmpty || !autoPauseEnabled {
                pausedByUs = true
                scheduleResume(after: Self.resumeRetryDelay, retriesLeft: retriesLeft - 1)
            } else {
                // Given up: the Mac's volume isn't left lowered for music that doesn't play.
                volumeLeveler?.restoreNow()
            }
        }
        publishPlaybackState()
        if resumeTask == resuming { resumeTask = nil } // unless a newer resume started meanwhile
    }
}
