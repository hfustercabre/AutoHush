import SwiftUI
import AutoHushKit
import CheckedPlayers

/// Settings → Media Player: the chosen player's card, above the tiles (B1,
/// the user's pick, 2026-11-05): "Use backup controls" and, under it, "Use
/// the Now Playing panel while muted" (dimmed, with a note, while the first
/// is off), then Details… (its controls in a sheet), and Restore Defaults
/// once one is off (the user, 2026-11-05). An app added before
/// backup controls were kept: dimmed, with Check Again…; a web app not
/// learned yet: dimmed, with "Controls not learned". No card while no player
/// is chosen, nor for one that's only muted.
struct PlayerControlsCard: View {
    let model: SettingsModel
    @State private var showsDetails = false

    var body: some View {
        if let controls = model.chosenControls, let name = model.chosenPlayerName {
            Card(Text(verbatim: name)) {
                if controls.needsCheckAgain {
                    SwitchRow(Text(verbatim: BackupText.uses), isOn: .constant(false)).unavailable(true)
                    NoteLabel(BackupText.checkAgain(name), kind: .info)
                    Button { model.actions?.checkPlayerAgain() } label: { Text(verbatim: ControlErrorFix.checkAgain.title) }
                        .buttonStyle(.chip)
                } else if controls.notLearned {
                    SwitchRow(Text(verbatim: BackupText.uses), isOn: .constant(false)).unavailable(true)
                    NoteLabel(AppStatus.controlsNotLearnedLine, kind: .info)
                } else {
                    SwitchRow(Text(verbatim: BackupText.uses), subtitle: Text(verbatim: BackupText.usesSubtitle),
                              isOn: switchBinding(controls, \.usesBackups))
                    if controls.hasPanel {
                        DependentRow {
                            VStack(alignment: .leading, spacing: 4) {
                                SwitchRow(Text(verbatim: BackupText.panelWhileMuted), subtitle: Text(verbatim: BackupText.panelSubtitle),
                                          isOn: switchBinding(controls, \.panelWhileMuted))
                                    .unavailable(!controls.switches.usesBackups)
                                if !controls.switches.usesBackups { NoteLabel(BackupText.off, kind: .info) }
                            }
                        }
                    }
                }
                Button { showsDetails = true } label: { Text(verbatim: BackupText.details) }
                    .buttonStyle(.chip)
            } footer: {
                RestoreDefaultsButton(model: model, card: .playerControls)
            }
            .sheet(isPresented: $showsDetails) {
                ControlDetailsView(player: name, controls: controls) { showsDetails = false }
            }
        }
    }

    /// One of its switches, set through AutoHush (an added app's setup keeps it).
    private func switchBinding(_ controls: PlayerControls, _ path: WritableKeyPath<BackupSwitches, Bool>) -> Binding<Bool> {
        Binding(get: { (model.chosenControls ?? controls).switches[keyPath: path] }, set: { value in
            var switches = (model.chosenControls ?? controls).switches
            switches[keyPath: path] = value
            model.actions?.setBackupSwitches(switches)
        })
    }
}
