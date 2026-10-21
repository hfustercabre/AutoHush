import SwiftUI

/// Settings → Calls, a grouped form (its own page from 2026-10-21, the
/// user's): pausing for the microphone and staying paused after a call
/// (greyed out while nothing resumes). Restore Defaults turns both off.
struct CallsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            Card {
                SettingsSwitchRow(model: model, kind: .pausesForMicrophone)
                CardDivider()
                SettingsSwitchRow(model: model, kind: .staysPausedAfterCalls)
                if let reason = SettingsSwitch.staysPausedAfterCalls.unavailableReason(model) {
                    NoteLabel(reason, kind: .info)
                }
            } footer: {
                RestoreDefaultsButton(isDefault: model.callsAreDefaults) { model.restoreDefaultCalls() }
            }
        }
    }
}
