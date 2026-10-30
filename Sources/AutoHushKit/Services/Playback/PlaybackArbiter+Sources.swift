import Foundation

// PlaybackArbiter: the apps that start or stop playing, and their calls.
extension PlaybackArbiter {
    /// Records that a source started or stopped. Returns without waiting for
    /// the pause it may start (`waitForPause()` does).
    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date? = nil) async {
        guard !isShutDown, configuration.isMediaSource(sourceID) else { return }

        if isPlaying {
            resumeFailure = nil // a new pause for this app, if any
            if let heardSince { latestStart = (heardSince, clock()) }
            // With auto-pause off, music we paused comes back regardless.
            if autoPauseEnabled { cancelPendingResume() }
            cancelPendingPause() // this app pauses the music now
            if activeSources.isEmpty { appsPlayingSince = clock() }
            leftToUser = false // a new app: the player is paused for it, as any
            activeSources.insert(sourceID)
            logActiveSources(after: "\(sourceID) started playing")
            noteCalls()
            guard !isAsleep else {
                publishPlaybackState()
                return
            }
            // The music may be coming back up after a cancelled fade-out: stop
            // that, so the pause in progress fades out again.
            if isFadingOut { await fader.stopComeback() }
            startPause() // publishes the outcome
        } else {
            activeSources.remove(sourceID)
            logActiveSources(after: "\(sourceID) stopped playing")
            if isAsleep {
                publishPlaybackState()
            } else if activeSources.isEmpty {
                pauseFailure = nil // nothing to pause for any more
                appsPlayingSince = nil
                leftToUser = false
                heardWhileQuietSince = nil
                // Measured no more: a player playing silently is what it says
                // it is again, playing (the user, 2026-10-26).
                let wasSilent = playsSilently
                playsSilently = false
                // Stopped during the fade-out: the music comes back up unpaused.
                if isFadingOut { await fader.cancel() }
                scheduleResume(after: nil)
                if wasSilent { publishPlaybackState() }
            } else {
                publishPlaybackState()
            }
        }
    }

    func handleCallChange(sourceID: String, inCall: Bool) async {
        guard !isShutDown else { return }
        if inCall { callSources.insert(sourceID) } else { callSources.remove(sourceID) }
        logger.info("[arbiter] \(sourceID, privacy: .public) \(inCall ? "is in a call (its microphone is on)" : "is no longer in a call", privacy: .public)")
        noteCalls()
    }

    /// Notes a call among the apps playing while the music is paused by us,
    /// or fades out to be.
    func noteCalls() {
        guard pausedByUs || isFadingOut, !callDuringPause, !callSources.isDisjoint(with: activeSources) else { return }
        callDuringPause = true
        logger.info("[arbiter] a call came during the pause")
    }

    /// Pauses and resumes, and why, are kept in AutoHush's log (info and
    /// up); the steps between them are only for a live `log stream` (debug).
    private func logActiveSources(after change: String) {
        logger.info("[arbiter] \(change, privacy: .public) (playing now: \(self.playingApps, privacy: .public))")
    }

    /// The apps playing now, for the log: their bundle IDs, or "none".
    var playingApps: String {
        activeSources.isEmpty ? "none" : activeSources.sorted().joined(separator: ", ")
    }
}
