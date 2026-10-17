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
                SwitchRow(
                    Text("Level the music", comment: "Settings → Advanced and Diagnostics: the switch that lowers the Mac’s volume as your music resumes after quieter apps"),
                    subtitle: Text("After quieter apps, it resumes with the Mac’s volume lowered to match, until the next pause. Calls don’t count.",
                                   comment: "Settings → Advanced, under “Level the music”; a call is an app using the microphone"),
                    isOn: binding(\.levelsMusic)
                )
                .disabled(model.isAntiDotMode)
                if model.isAntiDotMode {
                    NoteLabel(String(localized: "Off in AntiDot mode, which doesn’t measure sound.",
                                     comment: "Settings → Advanced, under the dimmed “Level the music”"),
                              kind: .info)
                }
            }
            Card {
                SwitchRow(
                    Text("Stay paused after calls", comment: "Settings → Advanced and Diagnostics: the switch that keeps your music paused after a call"),
                    subtitle: Text("Your music doesn’t resume when a call came while it was paused.",
                                   comment: "Settings → Advanced, under “Stay paused after calls”; a call is an app using the microphone"),
                    isOn: binding(\.staysPausedAfterCalls)
                )
            }
            RestoreDefaultsButton(isDefault: model.advancedAreDefaults) { model.restoreDefaultAdvanced() }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<TimingSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.timings[keyPath: keyPath] },
            set: { isOn in
                var timings = model.timings
                timings[keyPath: keyPath] = isOn
                model.setTimings(timings)
            }
        )
    }
}
