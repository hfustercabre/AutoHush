import SwiftUI
import AutoHushKit

/// Settings → Fine-Tuning, under Advanced (S5d + S5a, the user's pick,
/// 2026-10-25): what Behavior's switches use, a card each, each with its
/// Restore Defaults. Timing: how long another app must play, and be quiet
/// (greyed out while nothing resumes). Fade Lengths: greyed out while the
/// fades are off or the player can't fade. Volume Limits: leveling's,
/// greyed out while it's off or can't be. Detection: AntiDot mode's ways
/// (greyed out while it's off) and the silence threshold (greyed out in
/// it). What's greyed out says why, as in Behavior. A Behavior row opens it
/// scrolled to its card (`SettingsModel.fineTuningFocus`).
struct FineTuningSettingsView: View {
    let model: SettingsModel

    /// Its cards, by what Behavior's rows open.
    enum Part: Hashable {
        case timing, fadeLengths, volumeLimits, detection
    }

    var body: some View {
        SettingsPageScroll {
            Card(Self.timingTitle) {
                TimingSliderRow(model: model, timing: .pauseAfter)
                    .background(anchor(.timing))
                    // Always made: where the page is scrolled from.
                    .background(ScrollDriver(target: model.fineTuningFocus.map(AnyHashable.init)))
                CardDivider()
                TimingSliderRow(model: model, timing: .resumeAfter)
                    .unavailable(!model.timings.resumesPlayback)
                if !model.timings.resumesPlayback {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.timingIsDefault) { model.restoreDefaultTiming() }
            }

            Card(Self.fadeLengthsTitle) {
                Group {
                    TimingSliderRow(model: model, timing: .fadeOut)
                        .background(anchor(.fadeLengths))
                    CardDivider()
                    TimingSliderRow(model: model, timing: .fadeIn)
                        .unavailable(SettingsTiming.fadeInUnused(model))
                }
                .unavailable(!model.timings.fadesEnabled || !model.playerCanFade)
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(BehaviorSettingsView.cantFadeNote(player), kind: .info)
                } else if !model.timings.fadesEnabled {
                    NoteLabel(SettingsSwitch.fadesOffNote, kind: .info)
                } else if SettingsTiming.fadeInUnused(model) {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.fadeLengthsAreDefaults) { model.restoreDefaultFadeLengths() }
            }

            Card(Self.volumeLimitsTitle) {
                Group {
                    TimingSliderRow(model: model, timing: .levelingMaxCut)
                        .background(anchor(.volumeLimits))
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMinCut)
                }
                .unavailable(SettingsTiming.levelingLimitsUnavailable(model))
                if let reason = SettingsSwitch.levelsMusic.unavailableReason(model) {
                    NoteLabel(reason, kind: .info)
                } else if !model.timings.levelsMusic {
                    NoteLabel(SettingsSwitch.levelingOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.volumeLimitsAreDefaults) { model.restoreDefaultVolumeLimits() }
            }

            Card(Text(verbatim: DetectionText.title)) {
                // AntiDot mode's ways: greyed out while it's off, what each
                // does only while it's on.
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: DetectionText.detectByTitle) // a row's title
                    ChoiceChips(
                        label: DetectionText.detectByTitle,
                        options: DetectionMethod.antiDotWays.map { .init(title: $0.title, value: $0) },
                        selection: model.detectionMethod,
                        onSelect: { model.setDetectionMethod($0) }
                    )
                }
                // ← and → choose, while the arrow keys' highlight is on it.
                .highlightableRow(adjust: { step in
                    if let method = DetectionMethod.antiDotWays.stepping(from: model.detectionMethod, by: step) {
                        model.setDetectionMethod(method)
                    }
                })
                .unavailable(!model.isAntiDotMode)
                
                if model.isAntiDotMode {
                    Text(model.detectionMethod.summary).captionStyle()
                } else {
                    NoteLabel(SettingsSwitch.antiDotOffNote, kind: .info)
                }
                CardDivider()
                // Only measuring audio levels has a threshold: greyed out in AntiDot mode.
                TimingSliderRow(model: model, timing: .silenceThreshold)
                    .unavailable(model.isAntiDotMode)
            } footer: {
                RestoreDefaultsButton(isDefault: model.detectionIsDefault) { model.restoreDefaultDetection() }
            }
        }
    }

    /// Where the page scrolls to when a Behavior row asks for `part`: its
    /// card's first row (`ScrollDriver`; the request is cleared once another
    /// page shows).
    private func anchor(_ part: Part) -> some View {
        ScrollAnchor(id: AnyHashable(part))
    }

    static var timingTitle: Text {
        Text("Timing", comment: "Settings → Fine-Tuning: heading over how long another app must play before your player pauses, and be quiet before it resumes")
    }

    static var fadeLengthsTitle: Text {
        Text("Fade Lengths", comment: "Settings → Fine-Tuning: heading over how long playback fades out and back in")
    }

    static var volumeLimitsTitle: Text {
        Text("Volume Limits", comment: "Settings → Fine-Tuning: heading over Level the volume's limits (how much it lowers the Mac's volume at most, and from how much quieter on)")
    }
}
