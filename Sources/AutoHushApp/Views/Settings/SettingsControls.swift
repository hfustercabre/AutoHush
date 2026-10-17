import SwiftUI
import AutoHushKit

/// The switches Settings → Detection, → Fades and → Advanced share with the
/// menu's More Settings: the same words, and the same rules for when one
/// can't be changed.
enum SettingsSwitch: CaseIterable {
    case antiDot, fades, levelsMusic, staysPausedAfterCalls

    var title: Text {
        switch self {
        case .antiDot:
            Text("AntiDot mode", comment: "Settings → Detection and Diagnostics: the switch for AntiDot mode, which hides the purple recording indicator")
        case .fades:
            Text("Fade playback", comment: "Settings → Fades: the switch that turns the fades on or off")
        case .levelsMusic:
            Text("Level the music", comment: "Settings → Advanced and Diagnostics: the switch that lowers the Mac’s volume as your music resumes after quieter apps")
        case .staysPausedAfterCalls:
            Text("Stay paused after calls", comment: "Settings → Advanced and Diagnostics: the switch that keeps your music paused after a call")
        }
    }

    /// What it does, under it in Settings (the menu leaves it out).
    var subtitle: Text {
        switch self {
        case .antiDot:
            Text("Hides the purple recording indicator. Detection is less precise.",
                 comment: "Settings, under AntiDot mode")
        case .fades:
            Text("Out before pausing, and back in when resuming.",
                 comment: "Settings → Fades, under “Fade playback”")
        case .levelsMusic:
            Text("After quieter apps, it resumes with the Mac’s volume lowered to match, until the next pause. Calls don’t count.",
                 comment: "Settings → Advanced, under “Level the music”; a call is an app using the microphone")
        case .staysPausedAfterCalls:
            Text("Your music doesn’t resume when a call came while it was paused.",
                 comment: "Settings → Advanced, under “Stay paused after calls”; a call is an app using the microphone")
        }
    }

    /// What it does in a few words, under it in the menu (Settings has `subtitle`).
    var shortExplanation: Text {
        switch self {
        case .antiDot:
            Text("No purple dot, less precise.", comment: "The menu, under AntiDot mode: what it does, in a few words")
        case .fades:
            Text("Fades out and back in.", comment: "The menu, under Fade playback: what it does, in a few words")
        case .levelsMusic:
            Text("Matches quieter apps’ volume.", comment: "The menu, under Level the music: what it does, in a few words (it lowers the Mac’s volume as the music resumes after quieter apps)")
        case .staysPausedAfterCalls:
            Text("No resume after a call.", comment: "The menu, under Stay paused after calls: what it does, in a few words")
        }
    }

    /// Its symbol in the menu, in the accent color while it's on.
    var symbol: String {
        switch self {
        case .antiDot: "eye.slash"
        case .fades: "wave.3.right"
        case .levelsMusic: "slider.horizontal.below.rectangle"
        case .staysPausedAfterCalls: "phone.down"
        }
    }

    /// Off and dimmed: AntiDot mode with a player only its sound tells
    /// about, the fades with a player AutoHush can't fade, leveling in
    /// AntiDot mode (which measures no sound).
    @MainActor func isUnavailable(_ model: SettingsModel) -> Bool {
        switch self {
        case .antiDot: !model.isAntiDotMode && model.antiDotUnavailableFor != nil
        case .fades: !model.playerCanFade
        case .levelsMusic: model.isAntiDotMode
        case .staysPausedAfterCalls: false
        }
    }

    @MainActor func isOn(_ model: SettingsModel) -> Bool {
        switch self {
        case .antiDot: model.isAntiDotMode
        case .fades: model.timings.fadesEnabled
        case .levelsMusic: model.timings.levelsMusic
        case .staysPausedAfterCalls: model.timings.staysPausedAfterCalls
        }
    }

    @MainActor func set(_ isOn: Bool, in model: SettingsModel) {
        var timings = model.timings
        switch self {
        case .antiDot: return model.setAntiDotMode(isOn)
        case .fades: timings.fadesEnabled = isOn
        case .levelsMusic: timings.levelsMusic = isOn
        case .staysPausedAfterCalls: timings.staysPausedAfterCalls = isOn
        }
        model.setTimings(timings)
    }
}

/// One of `SettingsSwitch`, with what it does under it (`showsSubtitle`).
struct SettingsSwitchRow: View {
    let model: SettingsModel
    let kind: SettingsSwitch
    var showsSubtitle = true

    var body: some View {
        SwitchRow(kind.title, subtitle: showsSubtitle ? kind.subtitle : nil,
                  isOn: Binding(get: { kind.isOn(model) }, set: { kind.set($0, in: model) }))
            .disabled(kind.isUnavailable(model))
    }
}

/// The timings Settings → Detection and → Fades share with the menu's More
/// Settings.
enum SettingsTiming {
    case pauseAfter, resumeAfter, silenceThreshold, fadeOut, fadeIn

    var title: Text {
        switch self {
        case .pauseAfter:
            Text("Pause playback after", comment: "Settings → Detection and Diagnostics: how long another app must play before your player pauses")
        case .resumeAfter:
            Text("Resume playback after", comment: "Settings → Detection and Diagnostics: how long other apps must be quiet before your player resumes")
        case .silenceThreshold:
            Text("Silence threshold", comment: "Settings → Detection and Diagnostics: the sound level below which an app counts as silent")
        case .fadeOut:
            Text("Fade out before pausing", comment: "Settings → Fades: slider for how long playback fades out before it pauses")
        case .fadeIn:
            Text("Fade in when resuming", comment: "Settings → Fades: slider for how long playback fades back in when it resumes")
        }
    }

    /// What it does, under it in Settings (the menu leaves it out).
    var help: Text {
        switch self {
        case .pauseAfter:
            Text("How long another app must be audible. Filters out short sounds apps play themselves; system notification sounds are always ignored.",
                 comment: "Settings → Detection, under “Pause playback after”")
        case .resumeAfter:
            Text("How long another app must be silent. Bridges gaps between tracks and videos.",
                 comment: "Settings → Detection, under “Resume playback after”")
        case .silenceThreshold:
            Text("Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off).",
                 comment: "Settings → Detection, under “Silence threshold”")
        case .fadeOut:
            Text("How long playback fades out before it pauses. 0 pauses it at once.",
                 comment: "Settings → Fades, under “Fade out before pausing”")
        case .fadeIn:
            Text("How long playback takes to fade back in once it resumes. 0 resumes at full volume.",
                 comment: "Settings → Fades, under “Fade in when resuming”")
        }
    }

    var keyPath: WritableKeyPath<TimingSettings, Double> {
        switch self {
        case .pauseAfter: \.startConfirmation
        case .resumeAfter: \.stopGrace
        case .silenceThreshold: \.silenceThresholdDB
        case .fadeOut: \.fadeOutDuration
        case .fadeIn: \.fadeInDuration
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .pauseAfter: TimingSettings.startConfirmationRange
        case .resumeAfter: TimingSettings.stopGraceRange
        case .silenceThreshold: TimingSettings.silenceThresholdRange
        case .fadeOut, .fadeIn: TimingSettings.fadeDurationRange
        }
    }

    var step: Double {
        switch self {
        case .pauseAfter: 0.25
        case .resumeAfter, .fadeOut, .fadeIn: 0.5
        case .silenceThreshold: 5
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .silenceThreshold: String(localized: "\(Int(value)) dB", comment: "A sound level in decibels")
        default: value.secondsText
        }
    }
}
