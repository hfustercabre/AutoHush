import Foundation
import AutoHushKit

// What the user sees for the engine's states and choices: menu bar icons,
// VoiceOver labels and menu text. The engine itself has no text for them.

/// How a state looks in the menu bar: its icon, its VoiceOver label and the
/// status line at the top of the menu.
struct StatePresentation: Equatable {
    let icon: MenuBarIcon
    let label: String
    let line: String
}

extension StatePresentation {
    /// While AutoHush starts, and until the player's state is known.
    static var starting: StatePresentation {
        StatePresentation(
            icon: .starting,
            label: String(localized: "AutoHush: starting", comment: "VoiceOver label of the menu bar icon"),
            line: String(localized: "Starting services")
        )
    }
}

extension PlaybackState {
    /// `player`: the music player, e.g. "Spotify"; `playing`: the apps that
    /// paused it.
    func presentation(player: String, playing: [String] = []) -> StatePresentation {
        switch self {
        case .unknown: // the player's state is not known yet: as when starting up
            return .starting
        case .musicPlaying:
            return StatePresentation(
                icon: .playing,
                label: String(localized: "AutoHush: music is playing", comment: "VoiceOver label of the menu bar icon"),
                // A key of its own: "%@ is playing" also completes "Spotify paused — %@".
                line: String(localized: "status.playerIsPlaying", defaultValue: "\(player) is playing",
                             comment: "Status line at the top of the menu; %@ is the music player, e.g. Spotify")
            )
        case .pausedByMonitor:
            return StatePresentation(
                icon: .pausedForApp,
                label: String(localized: "AutoHush: music paused", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "\(player) paused — \(AppStatus.describePlaying(playing))",
                             comment: "Status line at the top of the menu; the music player, e.g. Spotify, then which apps play, e.g. “VLC is playing”")
            )
        case .musicIdle:
            return StatePresentation(
                icon: .noMusic,
                label: String(localized: "AutoHush: no music playing", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "\(player) isn't playing",
                             comment: "Status line at the top of the menu; %@ is the music player, e.g. Spotify")
            )
        case .playingElsewhere:
            return StatePresentation(
                icon: .elsewhere,
                label: String(localized: "AutoHush: music is playing on another device",
                              comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "\(player) is playing on another device",
                             comment: "Status line at the top of the menu; %@ is the music player, e.g. Spotify")
            )
        }
    }
}

extension AppHealthState {
    /// How AutoHush looks until it is ready; `nil` once it is, when the menu
    /// follows `PlaybackState` instead.
    var presentation: StatePresentation? {
        switch self {
        case .starting:
            return .starting
        case .ready:
            return nil
        case .needsPlayer(let message):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: no music player chosen", comment: "VoiceOver label of the menu bar icon"),
                line: message
            )
        case .degraded(let message):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: degraded",
                              comment: "VoiceOver label of the menu bar icon: something keeps AutoHush from working"),
                line: message
            )
        case .needsPermission(let permission):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: needs permission", comment: "VoiceOver label of the menu bar icon"),
                line: permission.statusLine
            )
        case .failed(let message):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: failed", comment: "VoiceOver label of the menu bar icon"),
                line: message
            )
        }
    }
}

extension DetectionMode {
    /// The detection in effect, as Diagnostics names it.
    var statusLine: String {
        switch self {
        case .pending:         return String(localized: "Detection: open audio streams (verifying levels)")
        case .audioLevel:      return String(localized: "Detection: audio levels")
        case .unavailable:     return String(localized: "Detection: open audio streams (no audio level access)")
        case .playbackSignals: return String(localized: "Detection: what apps tell macOS")
        case .disabled:        return String(localized: "Detection: open audio streams only")
        }
    }
}

extension Permission {
    /// The menu item that leads the user to grant it.
    var grantTitle: String {
        switch self {
        case .automation(let player):
            return String(localized: "Allow \(player) Automation Access…",
                          comment: "Menu item; %@ is the music player, e.g. Spotify")
        case .accessibility:
            return String(localized: "Allow Accessibility Access…",
                          comment: "Menu item: lets AutoHush control a music player through its menu, e.g. TIDAL")
        case .systemAudioRecording:
            return String(localized: "Allow Audio Recording Access…", comment: "Menu item")
        }
    }

    /// The status line while it's missing.
    var statusLine: String {
        switch self {
        case .automation(let player):
            return String(localized: "Grant Automation access to control \(player)",
                          comment: "Status line; %@ is the music player, e.g. Spotify")
        case .accessibility(let player):
            return String(localized: "Grant Accessibility access to control \(player)",
                          comment: "Status line; %@ is the music player, e.g. TIDAL")
        case .systemAudioRecording:
            return String(localized: "Grant Audio Recording access", comment: "Status line")
        }
    }
}

extension AutoPauseSnooze {
    /// The choice in the menu's "Turn Off For" submenu.
    var title: String {
        switch self {
        case .fiveMinutes:
            return String(localized: "5 Minutes", comment: "In the menu: turn auto-pause off for 5 minutes")
        case .fifteenMinutes:
            return String(localized: "15 Minutes", comment: "In the menu: turn auto-pause off for 15 minutes")
        case .thirtyMinutes:
            return String(localized: "30 Minutes", comment: "In the menu: turn auto-pause off for 30 minutes")
        case .oneHour:
            return String(localized: "1 Hour", comment: "In the menu: turn auto-pause off for 1 hour")
        case .twentyFourHours:
            return String(localized: "24 Hours", comment: "In the menu: turn auto-pause off for 24 hours")
        }
    }

    /// When the snooze ends, with its preposition so that each language can
    /// place it in a sentence: "until 15:30" today, otherwise "until tomorrow
    /// 8:00" (a snooze lasts 24 hours at most).
    static func describeEnd(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "until \(time)", comment: "When auto-pause turns back on today; %@ is a time")
        }
        return String(localized: "until tomorrow \(time)", comment: "When auto-pause turns back on; %@ is a time")
    }
}
