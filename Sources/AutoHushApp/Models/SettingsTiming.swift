import SwiftUI
import AutoHushKit

/// The timings of Settings → Fine-Tuning, as Diagnostics and Behavior's
/// rows to them name them too.
enum SettingsTiming {
    case pauseAfter, resumeAfter, silenceThreshold, fadeOut, fadeIn, levelingMaxCut, levelingMinCut

    /// Its name: the slider's and Diagnostics' row's.
    var name: String {
        switch self {
        case .pauseAfter:
            String(localized: "Pause playback after", comment: "Settings → Fine-Tuning, and Diagnostics: how long another app must play before your player pauses")
        case .resumeAfter:
            String(localized: "Resume playback after", comment: "Settings → Fine-Tuning, and Diagnostics: how long other apps must be quiet before your player resumes")
        case .silenceThreshold:
            String(localized: "Silence threshold", comment: "Settings → Fine-Tuning, and Diagnostics: the sound level below which an app counts as silent")
        case .fadeOut:
            String(localized: "Fade out before pausing", comment: "Settings → Fine-Tuning, and Diagnostics: slider for how long playback fades out before it pauses")
        case .fadeIn:
            String(localized: "Fade in when resuming", comment: "Settings → Fine-Tuning, and Diagnostics: slider for how long playback fades back in when it resumes")
        case .levelingMaxCut:
            String(localized: "Lower by at most", comment: "Settings → Fine-Tuning, and Diagnostics, under Level the volume: slider for the most the Mac’s volume is lowered as your player resumes (in decibels)")
        case .levelingMinCut:
            String(localized: "Only when quieter by", comment: "Settings → Fine-Tuning, and Diagnostics, under Level the volume: slider for how much quieter the other apps must have been than your player for the volume to be lowered (in decibels)")
        }
    }

    /// `name` as a view's text.
    var title: Text { Text(verbatim: name) }

    /// What it does, under it in Settings.
    var help: Text {
        switch self {
        case .pauseAfter:
            Text("How long another app must be audible, so short sounds don’t pause your player.",
                 comment: "Settings → Fine-Tuning, under “Pause playback after”")
        case .resumeAfter:
            Text("How long another app must be silent. Bridges gaps between tracks and videos.",
                 comment: "Settings → Fine-Tuning, under “Resume playback after”")
        case .silenceThreshold:
            Text("Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off).",
                 comment: "Settings → Fine-Tuning, under “Silence threshold”")
        case .fadeOut:
            Text("How long playback fades out before it pauses. 0 pauses it at once.",
                 comment: "Settings → Fine-Tuning, under “Fade out before pausing”")
        case .fadeIn:
            Text("How long playback takes to fade back in once it resumes. 0 resumes at full volume.",
                 comment: "Settings → Fine-Tuning, under “Fade in when resuming”")
        case .levelingMaxCut:
            Text("The most the Mac’s volume goes down as your player resumes.",
                 comment: "Settings → Fine-Tuning, under “Lower by at most”")
        case .levelingMinCut:
            Text("Smaller differences leave the volume as it is.",
                 comment: "Settings → Fine-Tuning, under “Only when quieter by”: when the other apps were less quieter than this, the Mac’s volume isn’t lowered")
        }
    }

    var keyPath: WritableKeyPath<TimingSettings, Double> {
        switch self {
        case .pauseAfter: \.startConfirmation
        case .resumeAfter: \.stopGrace
        case .silenceThreshold: \.silenceThresholdDB
        case .fadeOut: \.fadeOutDuration
        case .fadeIn: \.fadeInDuration
        case .levelingMaxCut: \.levelingMaxCutDB
        case .levelingMinCut: \.levelingMinCutDB
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .pauseAfter: TimingSettings.startConfirmationRange
        case .resumeAfter: TimingSettings.stopGraceRange
        case .silenceThreshold: TimingSettings.silenceThresholdRange
        case .fadeOut, .fadeIn: TimingSettings.fadeDurationRange
        case .levelingMaxCut: TimingSettings.levelingMaxCutRange
        case .levelingMinCut: TimingSettings.levelingMinCutRange
        }
    }

    var step: Double {
        switch self {
        case .pauseAfter: 0.25
        case .resumeAfter, .fadeOut, .fadeIn: 0.5
        case .silenceThreshold: 5
        case .levelingMaxCut, .levelingMinCut: 1
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .silenceThreshold, .levelingMaxCut, .levelingMinCut: Self.decibels(value)
        default: value.secondsText
        }
    }

    /// A sound level, as "-60 dB": here, and in Diagnostics.
    static func decibels(_ value: Double) -> String {
        String(localized: "\(Int(value)) dB", comment: "A sound level in decibels")
    }

    /// The fade lengths greyed out, in Settings: the fades are off, or the
    /// player can't fade.
    @MainActor static func fadeLengthsUnavailable(_ model: SettingsModel) -> Bool {
        !model.timings.fadesEnabled || !model.playerCanFade
    }

    /// The fade-in greyed out on its own, in Settings: nothing
    /// resumes, while the fades otherwise apply.
    @MainActor static func fadeInUnused(_ model: SettingsModel) -> Bool {
        !model.timings.resumesPlayback && model.timings.fadesEnabled && model.playerCanFade
    }

    /// Level the volume's limits greyed out, in Settings: it's
    /// off, or can't be on.
    @MainActor static func levelingLimitsUnavailable(_ model: SettingsModel) -> Bool {
        !model.timings.levelsMusic || SettingsSwitch.levelsMusic.isUnavailable(model)
    }
}
