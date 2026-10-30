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

    /// A player that's muted instead of paused, while `playing` play.
    static func muted(playing: [String], microphone: Bool = false) -> StatePresentation {
        StatePresentation(
            icon: .pausedForApp,
            label: String(localized: "AutoHush: your player is muted", comment: "VoiceOver label of the menu bar icon, while the media player (one that can only be muted, or one muted in place of a pause that didn't take) is muted for another app"),
            line: String(localized: "Muted — \(PlaybackState.describePlaying(playing, microphone: microphone))",
                         comment: "At the top of the menu and in Settings → General's status line, under the media player (an app added with Add an App that can only be muted, or a player muted in place of a pause that didn't take); %@ says which apps play, e.g. “Safari is playing”")
        )
    }

    /// A player AutoHush paused, kept paused while Add an App checks an app,
    /// whose pauses and plays would otherwise resume it in their gaps.
    static var heldForCheck: StatePresentation {
        StatePresentation(
            icon: .pausedForApp,
            label: String(localized: "AutoHush: playback paused", comment: "VoiceOver label of the menu bar icon"),
            line: String(localized: "Paused while a check runs",
                         comment: "At the top of the menu, under the media player: AutoHush keeps it paused until Add an App’s check of another app ends")
        )
    }

    /// While something needs the user: VoiceOver says what the status line
    /// does ("AutoHush: Jukebox isn't running").
    static func needingAttention(_ line: String) -> StatePresentation {
        StatePresentation(icon: .attention, label: iconLabel(line), line: line)
    }

    /// The player is closed: its line, calmly (grey, as nothing needs the
    /// user), and the icon as while no music plays.
    static func playerClosed(_ line: String) -> StatePresentation {
        StatePresentation(icon: .noMusic, label: iconLabel(line), line: line)
    }

    /// The menu bar icon's VoiceOver label that says the status line: while
    /// something needs the user, the player is closed, and while Auto-Pause
    /// is off.
    static func iconLabel(_ line: String) -> String {
        String(localized: "AutoHush: \(line)",
               comment: "VoiceOver label of the menu bar icon while something needs the user, the media player is closed or Auto-Pause is off; %@ is the menu's status line, e.g. “Jukebox isn’t running”, “Choose a media player” or “Auto-Pause is off until 15:30”")
    }
}

extension PlaybackState {
    /// `playing`: the apps that paused the music. The line goes under the
    /// media player's name, so it doesn't repeat it.
    /// `microphone`: the one app playing counts only for its microphone.
    func presentation(playing: [String] = [], microphone: Bool = false) -> StatePresentation {
        switch self {
        case .unknown: // the player's state is not known yet: as when starting up
            return .starting
        case .musicPlaying:
            return StatePresentation(
                icon: .playing,
                label: String(localized: "AutoHush: your player is playing", comment: "VoiceOver label of the menu bar icon"),
                line: Self.playingLine
            )
        case .pausedByMonitor:
            return StatePresentation(
                icon: .pausedForApp,
                label: String(localized: "AutoHush: playback paused", comment: "VoiceOver label of the menu bar icon"),
                line: String(localized: "Paused — \(Self.describePlaying(playing, microphone: microphone))",
                             comment: "At the top of the menu, under the media player; %@ says which apps play, e.g. “Safari is playing”")
            )
        case .musicIdle:
            return StatePresentation(
                icon: .noMusic,
                label: String(localized: "AutoHush: nothing is playing", comment: "VoiceOver label of the menu bar icon"),
                line: Self.notPlayingLine
            )
        case .playingSilently:
            return StatePresentation(
                icon: .noMusic,
                label: String(localized: "AutoHush: your player is playing silently",
                              comment: "VoiceOver label of the menu bar icon: the media player says it plays, but nothing of it is heard (a muted trailer), so AutoHush doesn't pause it"),
                line: Self.playingSilentlyLine
            )
        case .playingElsewhere:
            return StatePresentation(
                icon: .elsewhere,
                label: String(localized: "AutoHush: your player is playing on another device",
                              comment: "VoiceOver label of the menu bar icon"),
                line: Self.playingElsewhereLine
            )
        case .pauseFailed:
            return .needingAttention(String(localized: "Couldn’t pause — \(Self.describePlaying(playing, microphone: microphone))",
                                            comment: "At the top of the menu, under the media player, when it refused to pause or failed to; %@ says which apps play, e.g. “Safari is playing”"))
        }
    }

    /// The player's state in its words, the same at the top of the menu,
    /// in Settings → General's status line and in Diagnostics.
    static var playingLine: String {
        String(localized: "Playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it's playing; and under an app that plays now in the Add an App window's list")
    }

    static var notPlayingLine: String {
        String(localized: "Not playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: nothing plays")
    }

    static var playingSilentlyLine: String {
        String(localized: "Playing silently",
               comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it says it plays, but nothing of it is heard (a muted trailer or preview), so AutoHush doesn't pause it")
    }

    static var playingElsewhereLine: String {
        String(localized: "Playing on another device",
               comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player, e.g. on a speaker or a phone it streams to")
    }

    /// "Safari is playing", "Safari and FaceTime are playing", "Safari and 2 other apps are playing";
    /// "Zoom is using the microphone" for one app that counts only for its
    /// microphone (`microphone`: Pause for the microphone, before it makes a sound).
    static func describePlaying(_ names: [String], microphone: Bool = false) -> String {
        switch names.count {
        case 0:
            return String(localized: "another app is playing", comment: "Completes “Paused — %@”")
        case 1 where microphone:
            return String(localized: "\(names[0]) is using the microphone",
                          comment: "Completes “Paused — %@”, when an app with its microphone on (a call) paused your player before playing any sound (Settings → Behavior → Pause for the microphone); %@ is the app")
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
        case .needsPlayer(let message), .degraded(let message), .retrying(let message), .failed(let message):
            return .needingAttention(message)
        case .playerClosed(let message):
            return .playerClosed(message)
        case .needsPermission(let permission):
            return .needingAttention(permission.missingLine)
        }
    }
}
