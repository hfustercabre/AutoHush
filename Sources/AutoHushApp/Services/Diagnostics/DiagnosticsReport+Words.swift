import Foundation
import AutoHushKit
import CheckedPlayers

// DiagnosticsReport: its words for states, ways and settings.
extension DiagnosticsReport {
    static var on: String { String(localized: "On", comment: "A setting that is on: in Diagnostics, and the choice that turns Auto-Pause on in Shortcuts (it reads “Turn Auto-Pause On”) and in the Focus filter") }
    static var off: String { String(localized: "Off", comment: "A setting that is off: in Diagnostics, and the choice that turns Auto-Pause off in Shortcuts (it reads “Turn Auto-Pause Off”) and in the Focus filter") }
    static var yes: String { String(localized: "Yes", comment: "Diagnostics: yes") }
    static var no: String { String(localized: "No", comment: "Diagnostics: no") }
    static var allowed: String { PermissionText.allowed }
    static var notAllowed: String { String(localized: "Not allowed", comment: "Diagnostics: a permission that isn't granted") }
    static var unknown: String { String(localized: "Unknown", comment: "Diagnostics: something AutoHush can't tell") }

    /// "playing, ignored" as a row's subtitle: "Playing, ignored".
    static func sentenceCase(_ text: String) -> String {
        text.prefix(1).localizedUppercase + text.dropFirst()
    }

    /// The media player's state, as Diagnostics shows it; `mutes`: muted
    /// instead of paused.
    static func describe(_ playback: PlaybackState, mutes: Bool) -> String {
        switch playback {
        case .musicPlaying:     return String(localized: "Playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it's playing; and under an app that plays now in the Add an App window's list")
        case .pausedByMonitor where mutes:
            return String(localized: "Muted by AutoHush", comment: "Diagnostics: the media player's state while AutoHush mutes it for another app (an app added with Add an App that can only be muted, or a player muted in place of a pause that didn't take)")
        case .pausedByMonitor:  return String(localized: "Paused by AutoHush", comment: "Diagnostics: the media player's state")
        case .musicIdle:        return String(localized: "Not playing", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: nothing plays")
        case .playingElsewhere: return String(localized: "Playing on another device", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player, e.g. through Spotify Connect")
        case .playingSilently:  return String(localized: "Playing silently", comment: "At the top of the menu, in Settings → General's status line and in Diagnostics, under the media player: it says it plays, but nothing of it is heard (a muted trailer or preview), so AutoHush doesn't pause it")
        case .pauseFailed:      return String(localized: "Playing: couldn’t pause it", comment: "Diagnostics: the media player's state when it refused to pause or failed to, while another app plays")
        case .unknown:          return unknown
        }
    }

    /// A way an app added with Add an App is controlled by, as its check
    /// names it.
    static func describe(_ way: PlayerSetup.Way) -> String {
        switch way {
        case .script: WayText.title(.script)
        case .menu: WayText.title(.menu)
        case .page: WayText.title(.page)
        case .panel: WayText.title(.panel)
        case .mute: PlayerOption.mutedInsteadLabel
        }
    }

    /// How AutoHush tells that apps play, right now.
    static func describe(_ detection: DetectionMode) -> String {
        switch detection {
        case .audioLevel:      return String(localized: "Audio levels", comment: "Diagnostics: a way to detect playing apps")
        case .pending:
            return String(localized: "Audio levels (starting)", comment: "Diagnostics: audio levels, before the first is measured")
        case .unavailable:
            return String(localized: "Open audio streams (no Audio Recording access)",
                          comment: "Diagnostics: the detection used while the audio recording permission is missing")
        case .playbackSignals: return DetectionMethod.playbackSignals.title
        case .disabled:        return DetectionMethod.openStreams.title
        }
    }

    /// How AutoHush judges an app.
    static func describe(_ state: ActiveAudioReport.Entry.State, isIgnored: Bool) -> String {
        switch (state, isIgnored) {
        case (.playing, false):
            return String(localized: "playing", comment: "Diagnostics: how AutoHush judges an app")
        case (.playing, true):
            return String(localized: "playing, ignored", comment: "Diagnostics: how AutoHush judges an app")
        case (.starting, false):
            return String(localized: "starting", comment: "Diagnostics: an app audible too briefly to count yet")
        case (.starting, true):
            return String(localized: "starting, ignored", comment: "Diagnostics: an app audible too briefly to count yet")
        case (.silent, false):
            return String(localized: "output open, silent", comment: "Diagnostics: how AutoHush judges an app")
        case (.silent, true):
            return String(localized: "output open, silent, ignored", comment: "Diagnostics: how AutoHush judges an app")
        }
    }

    /// What the judgement rests on.
    static func describe(_ evidence: ActiveAudioReport.Entry.Evidence) -> String {
        switch evidence {
        case .announcing:
            return String(localized: "tells macOS it’s playing",
                          comment: "Diagnostics: why an app counts as playing, in AntiDot mode or while levels aren't measured")
        case .notAnnouncing:
            return String(localized: "not telling macOS it’s playing",
                          comment: "Diagnostics: why an app counts as paused, in AntiDot mode or while levels aren't measured")
        case .level(let peak) where peak > 0:
            return String(localized: "\(Int((20 * log10(peak)).rounded())) dBFS",
                          comment: "Diagnostics: an app's loudest level, in decibels")
        case .level:
            return String(localized: "silence", comment: "Diagnostics: the level of an app that makes no sound")
        }
    }
}
