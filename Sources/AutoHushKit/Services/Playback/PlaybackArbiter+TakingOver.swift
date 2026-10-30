import Foundation

// PlaybackArbiter: taking over the pause of the AutoHush before this one.
extension PlaybackArbiter {
    /// Takes over the pause of the AutoHush that ran before this one, which
    /// quit to install an update while holding the music paused: if the
    /// player is still paused, it counts as paused by this arbiter, so the
    /// music comes back once no other app plays. Apps still playing are found
    /// again first; when none is, the music resumes after the longest start
    /// the monitor applies (3 s for sound without video in AntiDot mode)
    /// plus `takeOverMargin`. `false` when there was no pause to take over:
    /// the player isn't paused.
    @discardableResult
    func takeOverPause() async -> Bool {
        // Handed over while the Mac sleeps: forgotten, as any pause then.
        guard !isShutDown, !isAsleep else { return false }
        let state = await livePlayerState()
        guard !isShutDown, state == .paused else { return false }
        pausedByUs = true
        logger.info("[arbiter] took over the pause of the previous AutoHush")
        publishPlaybackState()
        if activeSources.isEmpty {
            if autoPauseEnabled { scheduleTakenOverResume(from: clock()) } else { scheduleResume(after: nil) }
        }
        return true
    }

    /// The monitor says how long an app must play, at most, before it
    /// counts. A pause taken over before it said (it starts after the
    /// takeover) waits that long for apps still playing.
    func handleStartConfirmationChange(_ longest: TimeInterval) {
        guard !isShutDown else { return }
        let known = startConfirmation
        longestStartConfirmation = longest
        if longest != known, let takenOver, takenOver.resume == pendingResumeID {
            scheduleTakenOverResume(from: takenOver.at)
        }
    }

    /// How long an app must play, at most, before the monitor counts it, as
    /// far as known: until it says, the user's start confirmation.
    var startConfirmation: TimeInterval {
        longestStartConfirmation ?? configuration.sourceStartConfirmation
    }

    /// Resumes a pause taken over at `takenOverAt` once the monitor, starting
    /// afresh, has had `startConfirmation` plus `takeOverMargin` to find an
    /// app still playing.
    private func scheduleTakenOverResume(from takenOverAt: Date) {
        let wait = startConfirmation + Self.takeOverMargin - clock().timeIntervalSince(takenOverAt)
        scheduleResume(after: max(wait, 0))
        takenOver = pendingResumeID.map { (takenOverAt, $0) }
    }
}
