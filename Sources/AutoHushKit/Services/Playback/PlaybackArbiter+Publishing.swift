import Foundation

// PlaybackArbiter: what it tells the app.
extension PlaybackArbiter {
    func publishPlaybackState() {
        onStatusUpdate(.playback(mapPlaybackState()))

        let needed = audioLevelsNeeded
        if needed != publishedAudioLevelsNeeded {
            publishedAudioLevelsNeeded = needed
            onAudioLevelsNeededChange(needed)
        }
        if pausedByUs != publishedPausedByUs {
            publishedPausedByUs = pausedByUs
            if !pausedByUs { callDuringPause = false; heldByMute = false; mutedWhileQuiet = false } // that pause is over
            // A mute standing for it, or kept through it, is lifted: the
            // player plays on, heard, or can be played.
            if !pausedByUs, endPauseMute() {
                let mute = playerMute
                // A mute made next awaits this one's lifting (`muteInsteadOfPause`).
                muteLift = Task { await mute?.unmute() }
            }
            onPausedByUsChange(pausedByUs)
        }
    }

    /// Audio levels only matter while they can change a decision: whether to
    /// pause a player playing on this Mac, or when to resume one we paused.
    /// Otherwise the monitor captures nothing (no recording indicator).
    private var audioLevelsNeeded: Bool {
        guard autoPauseEnabled, !isShutDown else { return false }
        return pausedByUs || (playerState == .playing && playsLocally)
    }

    private func mapPlaybackState() -> PlaybackState {
        // Held, our pause lasts while no app plays too (see `holdResumes`).
        if pausedByUs, !activeSources.isEmpty || resumesHeld { return .pausedByMonitor }
        if pauseFailure != nil, !activeSources.isEmpty { return .pauseFailed }
        if playerState == .playing, !playsLocally { return .playingElsewhere }
        if playerState == .playing, playsSilently { return silentWithoutState ? .musicIdle : .playingSilently }

        switch playerState {
        case .playing:                       return .musicPlaying
        case .paused, .stopped, .notRunning: return .musicIdle
        case .unknown:                       return .unknown
        }
    }
}
