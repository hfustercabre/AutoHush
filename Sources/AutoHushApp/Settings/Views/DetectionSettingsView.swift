import SwiftUI
import AutoHushKit

/// Settings → Detection, in cards like the menu's: AntiDot mode (with the
/// way of detecting while it's on, or the Audio Recording it needs while
/// it's off), then the timings: when another app counts as playing or
/// stopped, and the silence threshold while AntiDot mode is off. Restore
/// Defaults sets these timings back.
struct DetectionSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SwitchRow(
                    Text("AntiDot mode", comment: "Settings → Detection and Diagnostics: the switch for AntiDot mode, which hides the purple recording indicator"),
                    subtitle: Text("Hides the purple recording indicator. Detection is less precise.",
                                   comment: "Settings, under AntiDot mode"),
                    isOn: Binding(get: { model.isAntiDotMode }, set: { model.setAntiDotMode($0) })
                )
                // Measuring needs Audio Recording: without it, the way to allow it, or AntiDot mode.
                if !model.isAntiDotMode, !model.permissions.audio.isSatisfied {
                    NoteLabel(audioNote)
                    // Side by side when they fit, else one under the other.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { audioButtons }
                        VStack(alignment: .leading, spacing: 6) { audioButtons }
                    }
                }
                if model.isAntiDotMode {
                    CardDivider()
                    SectionLabel(Text("Detect playing apps by", comment: "Settings → Detection, AntiDot mode: lead-in to the ways of detecting playing apps"))
                    ChoiceChips(
                        options: [DetectionMethod.playbackSignals, .openStreams].map { .init(title: $0.title, value: $0) },
                        selection: model.detectionMethod,
                        onSelect: { model.setDetectionMethod($0) }
                    )
                    Text(model.detectionMethod.summary).captionStyle()
                }
            }

            SectionHeading(Text("Timing", comment: "Settings → Detection: heading of how long other apps must play or be quiet before your player pauses or resumes"))
            Card {
                TimingSliderRow(
                    model: model,
                    title: Text("Pause playback after", comment: "Settings → Detection and Diagnostics: how long another app must play before your player pauses"),
                    keyPath: \.startConfirmation, range: TimingSettings.startConfirmationRange, step: 0.25,
                    help: Text("How long another app must be audible. Filters out short sounds apps play themselves; system notification sounds are always ignored.",
                               comment: "Settings → Detection, under “Pause playback after”")
                )
                CardDivider()
                TimingSliderRow(
                    model: model,
                    title: Text("Resume playback after", comment: "Settings → Detection and Diagnostics: how long other apps must be quiet before your player resumes"),
                    keyPath: \.stopGrace, range: TimingSettings.stopGraceRange, step: 0.5,
                    help: Text("How long another app must be silent. Bridges gaps between tracks and videos.",
                               comment: "Settings → Detection, under “Resume playback after”")
                )
                // Only measuring audio levels has a threshold: hidden in AntiDot mode.
                if !model.isAntiDotMode {
                    CardDivider()
                    TimingSliderRow(
                        model: model,
                        title: Text("Silence threshold", comment: "Settings → Detection and Diagnostics: the sound level below which an app counts as silent"),
                        keyPath: \.silenceThresholdDB, range: TimingSettings.silenceThresholdRange, step: 5,
                        format: { String(localized: "\(Int($0)) dB", comment: "A sound level in decibels") },
                        help: Text("Quieter output counts as silence. Only used while measuring audio levels (AntiDot mode off).",
                                   comment: "Settings → Detection, under “Silence threshold”")
                    )
                }
            }
            RestoreDefaultsButton(isDefault: model.detectionTimingsAreDefaults) { model.restoreDefaultDetectionTimings() }
        }
    }

    @ViewBuilder private var audioButtons: some View {
        PermissionButton(model: model, permission: .systemAudioRecording, access: model.permissions.audio, long: true)
            .fixedSize()
        Button { model.useAntiDotMode() } label: { Text(verbatim: PermissionText.useAntiDot) }
            .buttonStyle(.chip)
            .fixedSize()
    }

    private var audioNote: String {
        model.permissions.audio == .needsReopen
            ? PermissionText.audioNote(.needsReopen)
            : String(localized: "Without Audio Recording access, a silent app with its sound open keeps your player paused.",
                     comment: "Settings → Detection, under AntiDot mode, while Audio Recording isn't allowed")
    }
}

/// The detection choices as Settings and Diagnostics describe them.
extension DetectionMethod {
    var title: String {
        switch self {
        case .audioLevels:
            return String(localized: "Measure audio levels", comment: "Settings: a way to detect playing apps")
        case .playbackSignals:
            return String(localized: "What apps tell macOS", comment: "Settings, AntiDot mode: a way to detect playing apps")
        case .openStreams:
            return String(localized: "Open audio streams only",
                          comment: "Settings, AntiDot mode: a way to detect playing apps")
        }
    }

    var summary: String {
        switch self {
        case .audioLevels:
            return String(localized: "Most accurate: a paused video stops counting as soon as it goes silent. macOS shows its purple recording indicator while AutoHush measures.",
                          comment: "Settings → Detection, under the ways of detecting playing apps: what measuring audio levels does")
        case .playbackSignals:
            return String(localized: "An app counts as playing while it tells macOS it's playing, and as paused once it stops, even with its audio still open. Apps that never tell macOS count while their audio is open. Sound without video must last at least 3 seconds before your player pauses, so notification sounds don't interrupt it.",
                          comment: "Settings → Detection, under the ways of detecting playing apps: how “What apps tell macOS” works")
        case .openStreams:
            return String(localized: "Any app with its audio open counts as playing, even when paused.",
                          comment: "Settings → Detection, under the ways of detecting playing apps: how “Open audio streams only” works")
        }
    }
}

