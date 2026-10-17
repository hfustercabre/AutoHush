import SwiftUI
import AutoHushKit

/// Settings → Fades, in a card like the menu's: a switch, and the fades'
/// lengths while it's on; dimmed for a player AutoHush can't fade. Restore
/// Defaults sets the fades back.
struct FadesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                Group {
                    SettingsSwitchRow(model: model, kind: .fades)
                    // The lengths show only while there's something to fade.
                    if model.timings.fadesEnabled && model.playerCanFade {
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeOut)
                        CardDivider()
                        TimingSliderRow(model: model, timing: .fadeIn)
                    }
                }
                .disabled(!model.playerCanFade)
                .opacity(model.playerCanFade ? 1 : 0.45) // a disabled switch alone barely shows it
                if !model.playerCanFade, let player = model.chosenPlayerName {
                    NoteLabel(String(localized: "\(player) pauses and resumes without fading: AutoHush can’t change its volume.",
                                     comment: "Settings → Fades, under the dimmed fade settings; %@ is the media player, e.g. TIDAL"),
                              kind: .info)
                }
            }
            RestoreDefaultsButton(isDefault: model.fadesAreDefaults) { model.restoreDefaultFades() }
        }
    }
}
