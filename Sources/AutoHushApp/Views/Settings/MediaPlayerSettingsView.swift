import SwiftUI

/// Settings → Media Player (W2, the user, 2026-10-25: once General's): every
/// player as tiles, the chosen one outlined, to choose another; Add an App…
/// and Add a Web App…, and Remove on an added one.
struct MediaPlayerSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPageScroll {
            PlayerTiles(options: model.offeredPlayers, selection: model.chosenPlayerID,
                        onSelect: { model.actions?.choosePlayer($0.bundleID) }, onAddWebApp: { model.actions?.openAddWebApp() },
                        onAddApp: { model.actions?.openAddApp() },
                        onRemove: { model.actions?.removeAddedApp($0.bundleID) })
        }
    }
}
