import SwiftUI
import AutoHushKit

/// Settings → Behavior, a grouped form (B, the user's pick, 2026-10-21;
/// memory `settings-layout`): how AutoHush acts, a card for each moment,
/// its switches only since S5d + S5a (the user's pick, 2026-10-25), what
/// they use in Fine-Tuning. Each card ends with a row naming those settings
/// and what they're set to, which shows them there (`FineTuningRow`, L4),
/// and has its own Restore Defaults, for its switches. Pausing: the
/// microphone and an output going away. Resuming: whether the player
/// resumes at all, and staying paused after calls (greyed out while nothing
/// resumes). Fades: the switch (dimmed for a player AutoHush can't fade).
/// Volume: leveling the music (off in AntiDot mode, which measures no
/// sound, and while nothing resumes). Modes: AntiDot mode
/// (`BehaviorSettingsView+Modes`).
struct BehaviorSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card(Self.pausingTitle) {
                SettingsSwitchRow(model: model, kind: .pausesForMicrophone)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .pausesOnDisconnect)
                CardDivider()
                FineTuningRow(title: SettingsTiming.pauseAfter.name, value: value(.pauseAfter)) { model.showFineTuning(.timing) }
            } footer: {
                RestoreDefaultsButton(isDefault: model.pausingAreDefaults) { model.restoreDefaultPausing() }
            }

            Card(Self.resumingTitle) {
                SettingsSwitchRow(model: model, kind: .resumesPlayback)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls)
                // Why what follows the switch is greyed out, as in the other
                // cards (the user, 2026-10-22; none before).
                if !model.timings.resumesPlayback {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
                CardDivider()
                FineTuningRow(title: SettingsTiming.resumeAfter.name,
                              value: model.timings.resumesPlayback ? value(.resumeAfter) : nil) { model.showFineTuning(.timing) }
            } footer: {
                RestoreDefaultsButton(isDefault: model.resumingAreDefaults) { model.restoreDefaultResuming() }
            }

            Card(Text(verbatim: Self.fadesTitle)) {
                SettingsSwitchRow(model: model, kind: .fades)
                    .unavailable(!model.playerCanFade)
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(Self.cantFadeNote(player), kind: .info)
                }
                CardDivider()
                FineTuningRow(title: Self.fadeLengthsRowTitle,
                              value: model.playerCanFade && model.timings.fadesEnabled ? fadeLengths : nil) {
                    model.showFineTuning(.fadeLengths)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.fadesAreDefaults) { model.restoreDefaultFades() }
            }

            Card(Self.volumeTitle) {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                if let reason = SettingsSwitch.levelsMusic.unavailableReason(model) {
                    NoteLabel(reason, kind: .info)
                }
                CardDivider()
                FineTuningRow(title: Self.volumeLimitsRowTitle,
                              value: SettingsTiming.levelingLimitsUnavailable(model) ? nil : volumeLimits) {
                    model.showFineTuning(.volumeLimits)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.volumeAreDefaults) { model.restoreDefaultVolume() }
            }

            modesCard
        }
    }

    /// A timing as its slider shows it ("0.5 s").
    func value(_ timing: SettingsTiming) -> String {
        timing.format(model.timings[keyPath: timing.keyPath])
    }

    private var fadeLengths: String {
        String(localized: "\(value(.fadeOut)) out, \(value(.fadeIn)) in",
               comment: "Settings → Behavior, Fades' row to Fine-Tuning: the fade lengths; the first %@ is the fade-out's (e.g. “1 s”), the second the fade-in's")
    }

    private var volumeLimits: String {
        String(localized: "\(value(.levelingMaxCut)) at most",
               comment: "Settings → Behavior, Volume's row to Fine-Tuning: the most Level the volume lowers the Mac's volume; %@ is it, e.g. “10 dB”")
    }

    /// Under the dimmed Fade playback, for a player AutoHush can't fade;
    /// Fine-Tuning's Fade Lengths too.
    static func cantFadeNote(_ player: String) -> String {
        String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
               comment: "Settings → Behavior and Fine-Tuning, under the dimmed fade settings; %@ is the media player, e.g. TIDAL")
    }

    static var fadeLengthsRowTitle: String {
        String(localized: "Fade lengths", comment: "Settings → Behavior, Fades' last row: opens Fine-Tuning at the fade lengths, which it shows after it")
    }

    static var volumeLimitsRowTitle: String {
        String(localized: "Volume limits", comment: "Settings → Behavior, Volume's last row: opens Fine-Tuning at Level the volume's limits, the most it lowers the volume after it")
    }

    /// Over the microphone and an output going away pausing your player.
    static var pausingTitle: Text {
        Text("Pausing", comment: "Settings → Behavior: heading over what else pauses your player (the microphone, an output going away)")
    }

    /// Over Resume playback and staying paused after calls.
    static var resumingTitle: Text {
        Text("Resuming", comment: "Settings → Behavior: heading over whether your player resumes once other apps go quiet, and staying paused after calls")
    }

    /// Over the fades; also, with a check, under the media player in
    /// Settings → General and at the foot of the menu's card, and a
    /// Diagnostics row.
    nonisolated static var fadesTitle: String {
        String(localized: "Fades", comment: "Settings → Behavior: heading over the fades' switch; also, with a check, under the media player in Settings → General and in the menu's card, and a Diagnostics row: whether AutoHush can fade the media player")
    }

    /// Over Level the volume.
    static var volumeTitle: Text {
        Text("Volume", comment: "Settings → Behavior: heading over Level the volume")
    }
}
