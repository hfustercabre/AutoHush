import SwiftUI

/// Settings → Advanced, a grouped form: leveling the music (off in AntiDot
/// mode, which measures no sound). Restore Defaults turns it off.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                if model.isAntiDotMode {
                    NoteLabel(AntiDotText.featureOff, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.advancedAreDefaults) { model.restoreDefaultAdvanced() }
            }
        }
    }
}
