import SwiftUI

/// Settings → Media Player (W2, the user, 2026-10-25: once General's): every
/// player as tiles, the chosen one outlined, to choose another; Add an App…
/// and Add a Web App…, and Remove on an added one. Above them, what the
/// chosen player lacks to be controlled, as General says it (U7a, the
/// user's pick, 2026-11-02), then a card of its name with one row to its
/// controls in Fine-Tuning, what they're set to as its value (F4 + F5, the
/// user's pick, 2026-11-05: the controls' card was here, B1).
struct MediaPlayerSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            ControlPermissionNote(model: model, ownCard: true)
            // As Fine-Tuning's card shows: not while no player is chosen, nor for one that's only muted.
            if let controls = model.chosenControls, let name = model.chosenPlayerName {
                Card(Text(verbatim: name)) {
                    FineTuningRow(model: model, card: .playerControls, title: BackupText.controls,
                                  value: BackupText.summary(controls))
                }
            }
            PlayerTiles(options: model.offeredPlayers, selection: model.chosenPlayerID,
                        onSelect: { model.actions?.choosePlayer($0.bundleID) }, onAddWebApp: { model.actions?.openAddWebApp() },
                        onAddApp: { model.actions?.openAddApp() },
                        onRemove: { model.actions?.removeAddedApp($0.bundleID) })
        }
        .onAppear { model.actions?.refreshPlayerControls() }
    }
}
