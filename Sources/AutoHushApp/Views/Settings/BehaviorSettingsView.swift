import SwiftUI
import AutoHushKit

/// Settings → Behavior, a grouped form (B, the user's pick, 2026-10-21;
/// memory `settings-layout`): how AutoHush acts, a card for each moment,
/// then how it tells that other apps play (W1, the user, 2026-10-25:
/// Detection's page is its last two cards, `BehaviorSettingsView+Detection`).
/// Each card's main switch comes first and what depends on it is indented
/// under it, without a description of its own (W3, 2026-10-25).
/// Pausing: how long another app must play, and the microphone and an
/// output going away pausing too. Resuming: whether the player resumes at
/// all, how long the apps must be quiet first, and staying paused after
/// calls (greyed out while nothing resumes). Fades: the switch and both
/// lengths (the fade-in greyed out while nothing resumes; all of it dimmed
/// for a player AutoHush can't fade). Volume: leveling the music and its
/// limits (off in AntiDot mode, which measures no sound, and while nothing
/// resumes). One Restore Defaults at the end restores the whole page but
/// AntiDot mode.
struct BehaviorSettingsView: View {
    let model: SettingsModel

    /// How far a setting that depends on a switch is indented under it.
    static let dependentIndent: CGFloat = 22

    var body: some View {
        SettingsPageScroll {
            Card(Self.pausingTitle) {
                TimingSliderRow(model: model, timing: .pauseAfter)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .pausesForMicrophone)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .pausesOnDisconnect)
            }

            Card(Self.resumingTitle) {
                SettingsSwitchRow(model: model, kind: .resumesPlayback)
                CardDivider()
                dependent(TimingSliderRow(model: model, timing: .resumeAfter, showsHelp: false))
                    .unavailable(!model.timings.resumesPlayback)
                CardDivider()
                dependent(SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls, showsSubtitle: false))
                // Why what follows the switch is greyed out, as in the other
                // cards (the user, 2026-10-22; none before).
                if !model.timings.resumesPlayback {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
            }

            Card(Text(verbatim: Self.fadesTitle)) {
                Group {
                    SettingsSwitchRow(model: model, kind: .fades)
                    // The lengths, greyed out while the fades are off (the whole
                    // card is, with a player AutoHush can't fade).
                    Group {
                        CardDivider()
                        dependent(TimingSliderRow(model: model, timing: .fadeOut, showsHelp: false))
                        CardDivider()
                        dependent(TimingSliderRow(model: model, timing: .fadeIn, showsHelp: false))
                            .unavailable(fadeInUnused)
                    }
                    .unavailable(!model.timings.fadesEnabled && model.playerCanFade)
                }
                .unavailable(!model.playerCanFade)
                if model.playerCanFade, !model.timings.fadesEnabled {
                    NoteLabel(SettingsSwitch.fadesOffNote, kind: .info)
                } else if fadeInUnused {
                    NoteLabel(SettingsSwitch.resumeOffNote, kind: .info)
                }
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
                                     comment: "Settings → Behavior, under the dimmed fade settings; %@ is the media player, e.g. TIDAL"),
                              kind: .info)
                }
            }

            Card(Self.volumeTitle) {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                Group {
                    CardDivider()
                    dependent(TimingSliderRow(model: model, timing: .levelingMaxCut, showsHelp: false))
                    CardDivider()
                    dependent(TimingSliderRow(model: model, timing: .levelingMinCut, showsHelp: false))
                }
                .unavailable(SettingsTiming.levelingLimitsUnavailable(model))
                if let reason = SettingsSwitch.levelsMusic.unavailableReason(model) {
                    NoteLabel(reason, kind: .info)
                } else if !model.timings.levelsMusic {
                    NoteLabel(SettingsSwitch.levelingOffNote, kind: .info)
                }
            }

            modesCard
            measuringCard
        }
    }

    /// A setting that depends on the switch above it, indented under it.
    private func dependent(_ row: some View) -> some View {
        row.padding(.leading, Self.dependentIndent)
    }

    /// The fade-in, greyed out on its own while nothing resumes (Resume
    /// playback off), when the rest isn't already.
    private var fadeInUnused: Bool { SettingsTiming.fadeInUnused(model) }

    /// Over how long another app must play and what else pauses your
    /// player, here and in the menu's settings.
    static var pausingTitle: Text {
        Text("Pausing", comment: "Settings → Behavior, and a section title in the menu's settings: heading over when your player pauses (how long another app must play, the microphone, an output going away)")
    }

    /// Over Resume playback, its wait and staying paused after calls, here
    /// and in the menu's settings.
    static var resumingTitle: Text {
        Text("Resuming", comment: "Settings → Behavior, and a section title in the menu's settings: heading over whether and when your player resumes once other apps go quiet")
    }

    /// Over the fades, here and in the menu's settings; also, with a check,
    /// under the media player in Settings → General and at the foot of the
    /// menu's card, and a Diagnostics row.
    nonisolated static var fadesTitle: String {
        String(localized: "Fades", comment: "Settings → Behavior, and a section title in the menu's settings: heading over playback's fade out and fade in; also, with a check, under the media player in Settings → General and at the foot of the menu's card, and a Diagnostics row: whether AutoHush can fade the media player")
    }

    /// Over Level the volume and its limits, here and in the menu's settings.
    static var volumeTitle: Text {
        Text("Volume", comment: "Settings → Behavior, and a section title in the menu's settings: heading over Level the volume and its limits")
    }
}
