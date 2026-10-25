import SwiftUI
import AutoHushKit

/// Settings → Behavior's last card, Modes: AntiDot mode (with the Audio
/// Recording measuring needs while it's off, or why it can't be turned on),
/// then the row to Fine-Tuning's Detection, AntiDot mode's ways and the
/// silence threshold (S5d + S5a, the user's pick, 2026-10-25; before, the
/// end of this page, and a Detection page before W1).
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
            CardDivider()
            FineTuningRow(model: model, part: .detection, title: DetectionText.title, value: detection)
        } footer: {
            RestoreDefaultsButton(isDefault: model.modesAreDefaults) { model.restoreDefaultModes() }
        }
    }

    /// How apps are detected: AntiDot mode's way, or the silence threshold.
    private var detection: String {
        model.isAntiDotMode
            ? model.detectionMethod.title
            : String(localized: "Silence below \(value(.silenceThreshold))",
                     comment: "Settings → Behavior, Modes' row to Fine-Tuning's Detection, while AntiDot mode is off: quieter output counts as silence; %@ is the threshold, e.g. “-60 dB”")
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
