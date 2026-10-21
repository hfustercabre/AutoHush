import SwiftUI
import AutoHushKit

/// Settings → Behavior, a grouped form (B, the user's pick, 2026-10-21;
/// memory `settings-layout`): how AutoHush acts, a card for each moment.
/// Pausing: how long another app must play, and the microphone and an
/// output going away pausing too. Resuming: whether the player resumes at
/// all, how long the apps must be quiet first, and staying paused after
/// calls (greyed out while nothing resumes). Fades: the switch and both
/// lengths (the fade-in greyed out while nothing resumes; all of it dimmed
/// for a player AutoHush can't fade). Volume: leveling the music and its
/// limits (off in AntiDot mode, which measures no sound, and while nothing
/// resumes). Each card's Restore Defaults restores its own settings only.
struct BehaviorSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card(Self.pausingTitle) {
                TimingSliderRow(model: model, timing: .pauseAfter)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .pausesForMicrophone)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .pausesOnDisconnect)
            } footer: {
                RestoreDefaultsButton(isDefault: model.pausingAreDefaults) { model.restoreDefaultPausing() }
            }

            Card(Self.resumingTitle) {
                SettingsSwitchRow(model: model, kind: .resumesPlayback)
                CardDivider()
                TimingSliderRow(model: model, timing: .resumeAfter)
                    .unavailable(!model.timings.resumesPlayback)
                CardDivider()
                // No note why these are greyed out: the switch above says it
                // (the user, 2026-10-21; Fades and Volume, other cards, have one).
                SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls)
            } footer: {
                RestoreDefaultsButton(isDefault: model.resumingAreDefaults) { model.restoreDefaultResuming() }
            }

            Card(Text(verbatim: Self.fadesTitle)) {
                Group {
                    SettingsSwitchRow(model: model, kind: .fades)
                    // The lengths, greyed out while the fades are off (the whole
                    // card is, with a player AutoHush can't fade).
                    Group {
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeOut)
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeIn)
                            .unavailable(fadeInUnused)
                    }
                    .unavailable(!model.timings.fadesEnabled && model.playerCanFade)
                }
                .unavailable(!model.playerCanFade)
                if fadeInUnused {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
                                     comment: "Settings → Behavior, under the dimmed fade settings; %@ is the media player, e.g. TIDAL"),
                              kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.fadesAreDefaults) { model.restoreDefaultFades() }
            }

            Card(Self.volumeTitle) {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                Group {
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMaxCut)
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMinCut)
                }
                .unavailable(!model.timings.levelsMusic || SettingsSwitch.levelsMusic.isUnavailable(model))
                if let reason = SettingsSwitch.levelsMusic.unavailableReason(model) {
                    NoteLabel(reason, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.volumeAreDefaults) { model.restoreDefaultVolume() }
            }
        }
    }

    /// The fade-in, greyed out on its own while nothing resumes (Resume
    /// playback off), when the rest isn't already.
    private var fadeInUnused: Bool {
        !model.timings.resumesPlayback && model.timings.fadesEnabled && model.playerCanFade
    }

    /// Over how long another app must play and what else pauses your
    /// player, here and in the menu's Behavior.
    static var pausingTitle: Text {
        Text("Pausing", comment: "Settings → Behavior and the menu's Behavior: heading over when your player pauses (how long another app must play, the microphone, an output going away)")
    }

    /// Over Resume playback, its wait and staying paused after calls, here
    /// and in the menu's Behavior.
    static var resumingTitle: Text {
        Text("Resuming", comment: "Settings → Behavior and the menu's Behavior: heading over whether and when your player resumes once other apps go quiet")
    }

    /// Over the fades, here and in the menu's Behavior; also, with a check,
    /// under the media player in Settings → General and at the foot of the
    /// menu's card, and a Diagnostics row.
    static var fadesTitle: String {
        String(localized: "Fades", comment: "Settings → Behavior and the menu's Behavior: heading over playback's fade out and fade in; also, with a check, under the media player in Settings → General and at the foot of the menu's card, and a Diagnostics row: whether AutoHush can fade the media player")
    }

    /// Over Level the volume and its limits, here and in the menu's Behavior.
    static var volumeTitle: Text {
        Text("Volume", comment: "Settings → Behavior and the menu's Behavior: heading over Level the volume and its limits")
    }
}
