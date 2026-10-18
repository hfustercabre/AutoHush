import SwiftUI
import AutoHushKit

/// Settings → Fades, a grouped form: a switch, and the fades'
/// lengths while it's on; dimmed for a player AutoHush can't fade. Restore
/// Defaults sets the fades back.
struct FadesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                Group {
                    SettingsSwitchRow(model: model, kind: .fades)
                    // The lengths, greyed out while the fades are off (the whole
                    // card is, with a player AutoHush can't fade).
                    Group {
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeOut)
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeIn)
                    }
                    .unavailable(!model.timings.fadesEnabled && model.playerCanFade)
                }
                .unavailable(!model.playerCanFade)
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
                                     comment: "Settings → Fades, under the dimmed fade settings; %@ is the media player, e.g. TIDAL"),
                              kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.fadesAreDefaults) { model.restoreDefaultFades() }
            }
        }
    }
}
