import SwiftUI
import AutoHushKit

/// Settings → Detection, a grouped form: AntiDot mode (with the
/// way of detecting while it's on, or the Audio Recording it needs while
/// it's off), then the timings: when another app counts as playing or
/// stopped, and the silence threshold while AntiDot mode is off. Restore
/// Defaults sets these timings back.
struct DetectionSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card(Self.modesTitle) {
                SettingsSwitchRow(model: model, kind: .antiDot)
                // A player only its sound tells (muted only, or a Now Playing row
                // that doesn't follow it): AntiDot mode hears none (the user, 2026-10-15/16);
                // the switch is off and dimmed (`SettingsSwitch.isUnavailable`).
                if !model.isAntiDotMode, let player = model.antiDotUnavailablePlayer {
                    Text(verbatim: Self.unavailableNote(player.name, mutes: player.pausesByMuting)).captionStyle()
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
                    Text(verbatim: Self.detectByTitle) // a row's title
                    ChoiceChips(
                        label: Self.detectByTitle,
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
                }
            }

            Card(Self.timingTitle) {
                TimingSliderRow(model: model, timing: .pauseAfter)
                CardDivider()
                TimingSliderRow(model: model, timing: .resumeAfter)
                // Only measuring audio levels has a threshold: greyed out in AntiDot mode.
                CardDivider()
                TimingSliderRow(model: model, timing: .silenceThreshold)
                    .unavailable(model.isAntiDotMode)
            } footer: {
                RestoreDefaultsButton(isDefault: model.detectionTimingsAreDefaults) { model.restoreDefaultDetectionTimings() }
            }
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

    /// Over AntiDot mode, here and in the menu's Detection.
    static var modesTitle: Text {
        Text("Modes", comment: "Settings → Detection and the menu: heading over AntiDot mode")
    }

    /// Over the timings, here and in the menu's Detection.
    static var timingTitle: Text {
        Text("Timing", comment: "Settings → Detection: heading of how long other apps must play or be quiet before your player pauses or resumes")
    }

    /// The title over AntiDot mode's ways, which VoiceOver hears with them (the menu's too).
    static var detectByTitle: String {
        String(localized: "Detect playing apps by", comment: "Settings → Detection, AntiDot mode: lead-in to the ways of detecting playing apps")
    }

    /// Under the AntiDot mode switch while it's off and dimmed: as the menu
    /// says why the player couldn't be controlled in AntiDot mode.
    static func unavailableNote(_ player: String, mutes: Bool = true) -> String {
        mutes ? AntiDotText.onlyMuted(player) : AntiDotText.onlyHeard(player)
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
    /// AntiDot mode's ways, in the order Settings and the menu offer them.
    static let antiDotWays: [DetectionMethod] = [.playbackSignals, .openStreams]

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
            return String(localized: "An app counts as playing while it tells macOS it’s playing, and as paused once it stops, even with its audio still open. Apps that never tell macOS count while their audio is open. Sound without video must last at least 3 seconds before your player pauses, so notification sounds don’t interrupt it.",
                          comment: "Settings → Detection, under the ways of detecting playing apps: how “What apps tell macOS” works")
        case .openStreams:
            return String(localized: "Any app with its audio open counts as playing, even when paused. Its audio must stay open at least 2 seconds before your player pauses, so notification sounds don’t interrupt it.",
                          comment: "Settings → Detection, under the ways of detecting playing apps: how “Open audio streams only” works")
        }
    }
}

