import SwiftUI
import AutoHushKit

/// Settings → Behavior's last two cards, how AutoHush tells that other apps
/// play (a page of their own, Detection, until W1, the user, 2026-10-25):
/// Modes, AntiDot mode (with the way of detecting while it's on, or the
/// Audio Recording it needs while it's off), then Measuring, the silence
/// threshold (greyed out in AntiDot mode), under which the page's one
/// Restore Defaults is.
extension BehaviorSettingsView {
    var modesCard: some View {
        Card(DetectionText.modesTitle) {
            SettingsSwitchRow(model: model, kind: .antiDot)
            // A player only its sound tells (muted only, or a Now Playing row
            // that doesn't follow it): AntiDot mode hears none (the user, 2026-10-15/16);
            // the switch is off and dimmed (`SettingsSwitch.isUnavailable`).
            if !model.isAntiDotMode, let player = model.antiDotUnavailablePlayer {
                Text(verbatim: DetectionText.unavailableNote(player.name, mutes: player.pausesByMuting)).captionStyle()
            }
            // Measuring needs Audio Recording: without it, the way to allow it, or AntiDot mode.
            if !model.isAntiDotMode, !model.permissions.audio.isSatisfied {
                NoteLabel(audioNote)
                FlowingButtons(spacing: 6) { audioButtons }
            }
            // AntiDot mode's ways: greyed out while it's off, what each does
            // only while it's on.
            CardDivider()
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
        }
    }

    /// Only measuring audio levels has a threshold: greyed out in AntiDot
    /// mode. The page ends with it, and with its Restore Defaults.
    var measuringCard: some View {
        Card(DetectionText.measuringTitle) {
            TimingSliderRow(model: model, timing: .silenceThreshold)
                .unavailable(model.isAntiDotMode)
        } footer: {
            RestoreDefaultsButton(isDefault: model.behaviorIsDefault) { model.restoreDefaultBehavior() }
        }
    }

    @ViewBuilder private var audioButtons: some View {
        PermissionButton(model: model, permission: .systemAudioRecording, access: model.permissions.audio, long: true)
            .fixedSize()
        if model.antiDotUnavailableFor == nil {
            Button { model.useAntiDotMode() } label: { Text(verbatim: PermissionText.useAntiDot) }
                .buttonStyle(.chip)
                .fixedSize()
        }
    }

    private var audioNote: String {
        model.permissions.audio == .needsReopen
            ? PermissionText.audioNote(.needsReopen)
            : String(localized: "Without Audio Recording access, a silent app with its sound open keeps your player paused.",
                     comment: "Settings → Behavior, under AntiDot mode, while Audio Recording isn't allowed")
    }
}
