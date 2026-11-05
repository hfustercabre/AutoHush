import Foundation
import AutoHushKit
import CheckedPlayers

/// The chosen player's backup controls in Settings → Media Player (the
/// user, 2026-11-05).
extension AppDelegate {
    func refreshPlayerControls() {
        let controls = (player as? any ControlsReporting)?.controls
        if status.chosenControls != controls { status.chosenControls = controls }
    }

    /// An added app's setup keeps them and its player follows them; a
    /// built-in player or a web app reads them at each press. Either way the
    /// player stays, with any pause AutoHush holds in it.
    func setBackupSwitches(_ switches: BackupSwitches) {
        guard let player else { return }
        if let added = player as? any AddedAppPlayer {
            checkedPlayers.setSwitches(switches, for: player.bundleID, player: added)
        } else {
            BackupSwitchesStore().set(switches, for: player.bundleID)
        }
        refreshPlayerControls()
        // A page among its backups needs the app's launch option only while they're used.
        followPlayerReopen()
    }

    func checkPlayerAgain() {
        if let url = status.chosenPlayer?.appURL { addApp.open(on: url) }
    }
}
