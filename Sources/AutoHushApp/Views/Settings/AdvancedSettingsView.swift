import SwiftUI
import AutoHushKit

/// Settings → Advanced, in cards like the menu's: leveling the music (off
/// in AntiDot mode, which measures no sound), and staying paused after a
/// call. Restore Defaults turns both off.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                if model.isAntiDotMode {
                    NoteLabel(String(localized: "Off in AntiDot mode, which doesn’t measure sound.",
                                     comment: "Settings → Advanced, under the dimmed “Level the music”"),
                              kind: .info)
                }
            }
            Card {
                SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls)
            }
            RestoreDefaultsButton(isDefault: model.advancedAreDefaults) { model.restoreDefaultAdvanced() }
        }
    }

}
