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
    @Environment(KeyHighlight.self) private var keyboard: KeyHighlight?

    var body: some View {
        SettingsPageScroll {
            Card(Self.timingTitle) {
                TimingSliderRow(model: model, timing: .pauseAfter, isCurrent: isFocus(.timing))
                    .background(anchor(.timing))
                    // Always made: where the page is scrolled from, once.
                    .background(ScrollDriver(target: model.fineTuningFocus.map(AnyHashable.init)) {
                        // Its row pressed with a key: the highlight goes on from this card.
                        if model.fineTuningFocusTakesHighlight { keyboard?.highlightCurrent() }
                        model.fineTuningFocus = nil
                        model.fineTuningFocusTakesHighlight = false
                    })
                CardDivider()
                TimingSliderRow(model: model, timing: .resumeAfter, isCurrent: isFocus(.timing))
                    .unavailable(!model.timings.resumesPlayback)
                if !model.timings.resumesPlayback {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(model: model, card: .timing)
            }

            Card(Self.fadeLengthsTitle) {
                Group {
                    TimingSliderRow(model: model, timing: .fadeOut, isCurrent: isFocus(.fadeLengths))
                        .background(anchor(.fadeLengths))
                    CardDivider()
                    TimingSliderRow(model: model, timing: .fadeIn, isCurrent: isFocus(.fadeLengths))
                        .unavailable(model.fadeInUnused)
                }
                .unavailable(model.fadeLengthsUnavailable)
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(SettingsSwitch.cantFadeNote(player), kind: .info)
                } else if !model.timings.fadesEnabled {
                    NoteLabel(SettingsSwitch.fadesOffNote, kind: .info)
                } else if model.fadeInUnused {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(model: model, card: .fadeLengths)
            }

            Card(Self.volumeLimitsTitle) {
                Group {
                    TimingSliderRow(model: model, timing: .levelingMaxCut, isCurrent: isFocus(.volumeLimits))
                        .background(anchor(.volumeLimits))
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMinCut, isCurrent: isFocus(.volumeLimits))
                }
                .unavailable(model.levelingLimitsUnavailable)
                if let reason = model.levelingUnavailableNote {
                    NoteLabel(reason, kind: .info)
                } else if !model.timings.levelsMusic {
                    NoteLabel(SettingsSwitch.levelingOffNote, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(model: model, card: .volumeLimits)
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
                .background(anchor(.detection))
                // ← and → choose, while the arrow keys' highlight is on it.
                .highlightableRow(adjust: { step in
                    if let method = DetectionMethod.antiDotWays.stepping(from: model.detectionMethod, by: step) {
                        model.setDetectionMethod(method)
                    }
                }, isCurrent: isFocus(.detection))
                .unavailable(!model.isAntiDotMode)

                if model.isAntiDotMode {
                    Text(model.detectionMethod.summary).captionStyle()
                } else {
                    NoteLabel(SettingsSwitch.antiDotOffNote, kind: .info)
                }
                CardDivider()
                // Only measuring audio levels has a threshold: greyed out in AntiDot mode.
                TimingSliderRow(model: model, timing: .silenceThreshold, isCurrent: isFocus(.detection))
                    .unavailable(model.isAntiDotMode)
            } footer: {
                RestoreDefaultsButton(model: model, card: .detection)
            }
        }
    }

    /// Where the page scrolls to when a Behavior row asks for `card`: its
    /// first row (`ScrollDriver`; the request is cleared once it's done, or
    /// another page shows).
    private func anchor(_ card: SettingsCard) -> some View {
        ScrollAnchor(id: AnyHashable(card))
    }

    /// `card`'s rows stand for what a Behavior row opened: the highlight
    /// goes to the first one that can take it.
    private func isFocus(_ card: SettingsCard) -> () -> Bool {
        { model.fineTuningFocus == card }
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
