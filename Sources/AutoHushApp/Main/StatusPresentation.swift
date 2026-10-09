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
            line: String(localized: "Starting services", comment: "Status line while AutoHush starts")
        )
    }
}

extension PlaybackState {
    /// `playing`: the apps that paused the music. The line goes under the
    /// music player's name, so it doesn't repeat it.
    func presentation(playing: [String] = []) -> StatePresentation {
        switch self {
        case .unknown: // the player's state is not known yet: as when starting up
            return .starting
        case .musicPlaying:
            return StatePresentation(
                icon: .playing,
                label: String(localized: "AutoHush: music is playing", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Playing", comment: "At the top of the menu, under the music player: it's playing")
            )
        case .pausedByMonitor:
            return StatePresentation(
                icon: .pausedForApp,
                label: String(localized: "AutoHush: music paused", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Paused — \(Self.describePlaying(playing))",
                             comment: "At the top of the menu, under the music player; %@ says which apps play, e.g. “Safari is playing”")
            )
        case .musicIdle:
            return StatePresentation(
                icon: .noMusic,
                label: String(localized: "AutoHush: no music playing", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Not playing", comment: "At the top of the menu, under the music player: nothing plays")
            )
        case .playingElsewhere:
            return StatePresentation(
                icon: .elsewhere,
                label: String(localized: "AutoHush: music is playing on another device",
                              comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Playing on another device",
                             comment: "At the top of the menu, under the music player, e.g. through Spotify Connect")
            )
        case .pauseFailed:
            return StatePresentation(
                icon: .attention,
                label: String(localized: "AutoHush: couldn't pause the music", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Couldn't pause — \(Self.describePlaying(playing))",
                             comment: "At the top of the menu, under the music player, when it refused to pause or failed to; %@ says which apps play, e.g. “Safari is playing”")
            )
        }
    }

    /// "VLC is playing", "VLC and Safari are playing", "VLC and 2 other apps are playing".
    static func describePlaying(_ names: [String]) -> String {
        switch names.count {
        case 0:
            return String(localized: "another app is playing", comment: "Completes “Paused — %@”")
        case 1:
            return String(localized: "\(names[0]) is playing", comment: "Completes “Paused — %@”; %@ is an app")
        case 2:
            return String(localized: "\(names[0]) and \(names[1]) are playing",
                          comment: "Completes “Paused — %@”; two apps")
        default:
            return String(localized: "\(names[0]) and \(names.count - 1) other apps are playing",
                          comment: "Completes “Paused — %@”; an app, then how many others (2 or more)")
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
        case .degraded(let message), .retrying(let message):
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

/// Why a player couldn't be controlled, the last time it couldn't: in the
/// user's language for the menu and Diagnostics, and in English (as the log
/// has it) for a bug report.
struct ControlError: Equatable {
    /// E.g. "AutoHush can't find Play/Pause in TIDAL's menus."
    let text: String
    /// E.g. "Controlling the music player failed: its Play/Pause menu item wasn't found."
    let detail: String

    init(text: String, detail: String) {
        self.text = text
        self.detail = detail
    }

    init(_ error: any Error, player: String) {
        detail = error.localizedDescription
        switch error as? MusicPlayerError {
        case .playerCommandFailed(let failure)?:
            text = failure.text(player: player)
        case .automationPermissionDenied?, .accessibilityPermissionDenied?:
            text = String(localized: "AutoHush may no longer control \(player).",
                          comment: "Why the music player couldn't be controlled: its permission was taken away; %@ is the player")
        case .playerNotRunning?:
            text = String(localized: "\(player) isn't running.",
                          comment: "Why the music player couldn't be controlled: it quit; %@ is the player")
        case .playerNotResponding?:
            text = String(localized: "\(player) isn't responding.",
                          comment: "Why the music player couldn't be controlled; %@ is the player")
        case .stillLearning?, nil:
            text = error.localizedDescription
        }
    }
}

extension ControlFailure {
    /// The failure as the user reads it, about `player`.
    func text(player: String) -> String {
        switch self {
        case .menuItemNotFound:
            String(localized: "AutoHush can't find Play/Pause in \(player)'s menus.",
                   comment: "Why the music player couldn't be controlled: an update may have changed its menus; %@ is the player, e.g. TIDAL")
        case .stateUnknown:
            String(localized: "\(player) doesn't say whether it's playing.",
                   comment: "Why the music player couldn't be controlled: its state can't be read; %@ is the player")
        case .nothingToPlay:
            String(localized: "\(player) has nothing to play.",
                   comment: "Why the music player couldn't be controlled: its Play is disabled; %@ is the player")
        case .buttonDisabled:
            String(localized: "\(player)'s Play/Pause button is disabled, as during an ad.",
                   comment: "Why a web app couldn't be paused: the site disabled its button; %@ is the web app")
        case .pressFailed:
            String(localized: "AutoHush couldn't press \(player)'s Play/Pause.",
                   comment: "Why the music player couldn't be controlled; %@ is the player")
        case .pressIgnored:
            String(localized: "\(player) didn't respond to its Play/Pause.",
                   comment: "Why the music player couldn't be controlled: a press didn't change it; %@ is the player")
        case .appleEventError(let number, _):
            String(localized: "\(player) answered with an error (\(String(number))).",
                   comment: "Why the music player couldn't be controlled; the first %@ is the player, the second the error's number, e.g. -1708")
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
            return String(localized: "Allow Automation access to control \(player)",
                          comment: "Status line; %@ is the music player, e.g. Spotify")
        case .accessibility(let player):
            return String(localized: "Allow Accessibility access to control \(player)",
                          comment: "Status line; %@ is the music player, e.g. TIDAL")
        case .systemAudioRecording:
            return String(localized: "Allow Audio Recording access", comment: "Status line")
        }
    }
}

extension AutoPauseSnooze {
    /// The duration on its button in the menu, e.g. "15 min" or "1 hr", in
    /// the user's language.
    var shortTitle: String {
        Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// The choice in full, e.g. "15 Minutes", as VoiceOver reads it.
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
