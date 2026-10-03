import Foundation
import AutoHushKit

// SF Symbols, accessibility labels and menu text for the app's states.

// `PlaybackState.unknown` looks like starting up: the player's state is not known yet.

extension PlaybackState {
    var symbolName: String {
        switch self {
        case .unknown:          return AppHealthState.starting.symbolName
        case .musicPlaying:     return "play.circle.fill"
        case .pausedByMonitor:  return "pause.circle.fill"
        case .musicIdle:        return "music.note"
        case .playingElsewhere: return "hifispeaker.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .unknown:          return AppHealthState.starting.accessibilityLabel
        case .musicPlaying:     return "AutoHush: music is playing"
        case .pausedByMonitor:  return "AutoHush: music paused"
        case .musicIdle:        return "AutoHush: no music playing"
        case .playingElsewhere: return "AutoHush: music is playing on another device"
        }
    }

    var statusLine: String {
        switch self {
        case .unknown:          return AppHealthState.starting.statusLine
        case .musicPlaying:     return "Music is playing"
        case .pausedByMonitor:  return "Music paused — another app is playing"
        case .musicIdle:        return "No music playing"
        case .playingElsewhere: return "Music is playing on another device"
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
