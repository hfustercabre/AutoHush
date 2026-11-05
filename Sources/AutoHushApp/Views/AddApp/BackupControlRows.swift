import SwiftUI
import AutoHushKit
import CheckedPlayers

/// Add an App's last step, under the ways to choose (B1, the user's pick,
/// 2026-11-05): "Use backup controls", and "Use the Now Playing panel while
/// muted" under it while it's on and the panel is among them. No Details…
/// here: the ways' cards above say how each did (the user, 2026-11-05: "it's
/// redundant"). Use keeps both switches.
struct BackupControlRows: View {
    let model: AddAppModel

    var body: some View {
        if let controls = model.backupControls {
            VStack(alignment: .leading, spacing: 6) {
                SwitchRow(Text(verbatim: BackupText.uses), subtitle: Text(verbatim: BackupText.usesSubtitle),
                          isOn: Binding(get: { model.backupSwitches.usesBackups }, set: { model.backupSwitches.usesBackups = $0 }))
                if model.backupSwitches.usesBackups, controls.hasPanel {
                    DependentRow {
                        SwitchRow(Text(verbatim: BackupText.panelWhileMuted), subtitle: Text(verbatim: BackupText.panelSubtitle),
                                  isOn: Binding(get: { model.backupSwitches.panelWhileMuted }, set: { model.backupSwitches.panelWhileMuted = $0 }))
                    }
                }
            }
        }
    }
}
