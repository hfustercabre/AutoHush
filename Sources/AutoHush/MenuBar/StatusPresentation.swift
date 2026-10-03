import Foundation

// SF Symbols, accessibility labels and menu text for the app's states.

extension PlaybackState {
    var symbolName: String {
        switch self {
        case .unknown:                 return "arrow.triangle.2.circlepath"
        case .spotifyPlaying:          return "play.circle.fill"
        case .pausedByMonitor:         return "pause.circle.fill"
        case .spotifyIdle:             return "music.note"
        case .spotifyPlayingElsewhere: return "hifispeaker.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown:                 return "AutoHush: starting"
        case .spotifyPlaying:          return "AutoHush: music is playing"
        case .pausedByMonitor:         return "AutoHush: music paused"
        case .spotifyIdle:             return "AutoHush: no music playing"
        case .spotifyPlayingElsewhere: return "AutoHush: music is playing on another device"
        }
    }

    var statusLine: String {
        switch self {
        case .unknown:                 return "Starting services"
        case .spotifyPlaying:          return "Music is playing"
        case .pausedByMonitor:         return "Music paused — another app is playing"
        case .spotifyIdle:             return "No music playing"
        case .spotifyPlayingElsewhere: return "Music is playing on another device"
        }
    }
}

extension AppHealthState {
    /// Used only when health is not `.ready`; then the icon follows `PlaybackState`.
    var symbolName: String {
        switch self {
        case .starting:        return "arrow.triangle.2.circlepath"
        case .ready:           return "speaker.wave.2.fill"
        case .degraded:        return "exclamationmark.triangle.fill"
        case .needsPermission: return "lock.trianglebadge.exclamationmark.fill"
        case .failed:          return "speaker.slash.fill"
        }
    }

    /// Used only when health is not `.ready`.
    var accessibilityLabel: String {
        switch self {
        case .starting:        return "AutoHush: starting"
        case .ready:           return "AutoHush: monitoring"
        case .degraded:        return "AutoHush: degraded"
        case .needsPermission: return "AutoHush: needs permission"
        case .failed:          return "AutoHush: failed"
        }
    }

    var statusLine: String {
        switch self {
        case .starting:          return "Starting services"
        case .ready:             return "Monitoring media playback"
        case .degraded(let m), .needsPermission(let m), .failed(let m):
            return m
        }
    }
}

extension DetectionMode {
    var statusLine: String {
        switch self {
        case .pending:         return "Detection: open audio streams (verifying levels)"
        case .audioLevel:      return "Detection: audio levels"
        case .unavailable:     return "Detection: open audio streams (no audio level access)"
        case .playbackSignals: return "Detection: what apps tell macOS"
        case .disabled:        return "Detection: open audio streams only"
        }
    }
}
