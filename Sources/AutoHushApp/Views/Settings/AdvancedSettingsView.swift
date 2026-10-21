import SwiftUI
import AutoHushKit

/// Settings → Advanced, a grouped form: under Volume, leveling the music, with how far it
/// lowers the volume at most and how much quieter the apps must have been
/// (greyed out while it's off; all of it off in AntiDot mode, which measures
/// no sound). Restore Defaults sets them back.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card(Self.volumeTitle) {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                Group {
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMaxCut)
                    CardDivider()
                    TimingSliderRow(model: model, timing: .levelingMinCut)
                }
                .unavailable(!model.timings.levelsMusic || model.isAntiDotMode)
                if model.isAntiDotMode {
                    NoteLabel(AntiDotText.featureOff, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.advancedAreDefaults) { model.restoreDefaultAdvanced() }
            }
        }
    }

    /// Over Level the volume and its limits, here and in the menu's Advanced.
    static var volumeTitle: Text {
        Text("Volume", comment: "Settings → Advanced and the menu's Advanced: heading over Level the volume and its limits")
    }
}
