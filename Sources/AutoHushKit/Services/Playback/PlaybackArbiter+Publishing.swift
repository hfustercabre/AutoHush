import Foundation
import OSLog

// PlaybackArbiter: what it tells the app.
extension PlaybackArbiter {
    func publishPlaybackState() {
        onPlaybackStateChange(mapPlaybackState())

        let needed = audioLevelsNeeded
        if needed != publishedAudioLevelsNeeded {
            publishedAudioLevelsNeeded = needed
            onAudioLevelsNeededChange(needed)
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
        if pausedByUs, !activeSources.isEmpty { return .pausedByMonitor }
        if pauseFailure != nil, !activeSources.isEmpty { return .pauseFailed }
        if playerState == .playing, !playsLocally { return .playingElsewhere }

        switch playerState {
        case .playing:                       return .musicPlaying
        case .paused, .stopped, .notRunning: return .musicIdle
        case .unknown:                       return .unknown
        }
    }
}
