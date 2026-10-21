import SwiftUI

/// Settings → Advanced, a grouped form: leveling the music (off
/// in AntiDot mode, which measures no sound), then Calls: pausing for the
/// microphone and staying paused after a call. Restore Defaults turns them
/// all off.
struct AdvancedSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SettingsSwitchRow(model: model, kind: .levelsMusic)
                if model.isAntiDotMode {
                    NoteLabel(AntiDotText.featureOff, kind: .info)
                }
            }
            Card(Self.callsTitle) {
                SettingsSwitchRow(model: model, kind: .pausesForMicrophone)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls)
            } footer: {
                RestoreDefaultsButton(isDefault: model.advancedAreDefaults) { model.restoreDefaultAdvanced() }
            }
        }
    }

    /// Over the two switches about calls, here and in the menu.
    static var callsTitle: Text {
        Text("Calls", comment: "Settings → Advanced and the menu: the heading over Pause for the microphone and Stay paused after calls")
    }
}
