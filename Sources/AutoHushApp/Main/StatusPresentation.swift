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
            return StatePresentation(icon: .playing, label: "AutoHush: music is playing", line: "Music is playing")
        case .pausedByMonitor:
            return StatePresentation(icon: .pausedForApp, label: "AutoHush: music paused",
                                     line: "Music paused — another app is playing")
        case .musicIdle:
            return StatePresentation(icon: .noMusic, label: "AutoHush: no music playing", line: "No music playing")
        case .playingElsewhere:
            return StatePresentation(icon: .elsewhere, label: "AutoHush: music is playing on another device",
                                     line: "Music is playing on another device")
        }
    }
}

extension AppHealthState {
    /// Shown while the app isn't `.ready`; then the menu follows `PlaybackState`.
    var presentation: StatePresentation {
        switch self {
        case .starting:
            return StatePresentation(icon: .starting, label: "AutoHush: starting", line: "Starting services")
        case .ready:
            return StatePresentation(icon: .playing, label: "AutoHush: monitoring", line: "Monitoring media playback")
        case .degraded(let message):
            return StatePresentation(icon: .attention, label: "AutoHush: degraded", line: message)
        case .needsPermission(let message):
            return StatePresentation(icon: .attention, label: "AutoHush: needs permission", line: message)
        case .failed(let message):
            return StatePresentation(icon: .attention, label: "AutoHush: failed", line: message)
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

extension Permission {
    /// The menu item that leads the user to grant it.
    var grantTitle: String {
        switch self {
        case .automation(let player): return "Allow \(player) Automation Access…"
        case .systemAudioRecording:   return "Allow Audio Recording Access…"
        }
    }
}

extension AutoPauseSnooze {
    /// The choice in the menu's "Turn Off For" submenu.
    var title: String {
        switch self {
        case .fifteenMinutes: return "15 Minutes"
        case .oneHour:        return "1 Hour"
        case .untilTomorrow:  return "Until Tomorrow"
        }
    }

    /// "15:30" today, "tomorrow 8:00", otherwise weekday and time.
    static func describeEnd(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let time = date.formatted(style)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(time)"
        }
        var weekday = Date.FormatStyle().weekday(.wide)
        weekday.timeZone = calendar.timeZone
        return "\(date.formatted(weekday)) \(time)"
    }
}
