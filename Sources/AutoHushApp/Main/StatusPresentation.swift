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

extension PlaybackState {
    var presentation: StatePresentation {
        switch self {
        case .unknown: // the player's state is not known yet: as when starting up
            return AppHealthState.starting.presentation
        case .musicPlaying:
            return StatePresentation(
                icon: .playing,
                label: String(localized: "AutoHush: music is playing", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Music is playing")
            )
        case .pausedByMonitor:
            return StatePresentation(
                icon: .pausedForApp,
                label: String(localized: "AutoHush: music paused", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Music paused — another app is playing")
            )
        case .musicIdle:
            return StatePresentation(
                icon: .noMusic,
                label: String(localized: "AutoHush: no music playing", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "No music playing")
            )
        case .playingElsewhere:
            return StatePresentation(
                icon: .elsewhere,
                label: String(localized: "AutoHush: music is playing on another device",
                              comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Music is playing on another device")
            )
        }
    }
}

extension AppHealthState {
    /// Shown while the app isn't `.ready`; then the menu follows `PlaybackState`.
    var presentation: StatePresentation {
        switch self {
        case .starting:
            return StatePresentation(
                icon: .starting,
                label: String(localized: "AutoHush: starting", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Starting services")
            )
        case .ready:
            return StatePresentation(
                icon: .playing,
                label: String(localized: "AutoHush: monitoring", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Monitoring media playback")
            )
        case .degraded(let message):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: degraded",
                              comment: "VoiceOver label of the menu bar icon: something keeps AutoHush from working"),
                line: message
            )
        case .needsPermission(let message):
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: needs permission", comment: "VoiceOver label of the menu bar icon"),
                line: message
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
        case .systemAudioRecording:
            return String(localized: "Allow Audio Recording Access…", comment: "Menu item")
        }
    }
}

extension AutoPauseSnooze {
    /// The choice in the menu's "Turn Off For" submenu.
    var title: String {
        switch self {
        case .fifteenMinutes:
            return String(localized: "15 Minutes", comment: "In the menu: turn auto-pause off for 15 minutes")
        case .oneHour:
            return String(localized: "1 Hour", comment: "In the menu: turn auto-pause off for 1 hour")
        case .untilTomorrow:
            return String(localized: "Until Tomorrow", comment: "In the menu: turn auto-pause off until tomorrow at 8:00")
        }
    }

    /// When the snooze ends, with its preposition so that each language can
    /// place it in a sentence: "until 15:30" today, "until tomorrow 8:00",
    /// otherwise "until Thursday 8:00".
    static func describeEnd(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "until \(time)", comment: "When auto-pause turns back on today; %@ is a time")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "until tomorrow \(time)", comment: "When auto-pause turns back on; %@ is a time")
        }
        var weekday = Date.FormatStyle().weekday(.wide)
        weekday.timeZone = calendar.timeZone
        return String(localized: "until \(date.formatted(weekday)) \(time)",
                      comment: "When auto-pause turns back on; a weekday, then a time")
    }
}
