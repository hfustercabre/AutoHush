import AppKit
import AutoHushKit

/// What the windows show about the permissions AutoHush needs, and a click
/// on a missing one's button (see `PermissionCenter`).
extension AppDelegate {
    /// Brings what the windows show about the permissions up to date.
    func refreshPermissions() async {
        let state = await permissionCenter.state(
            player: player, detectionMethod: preferences.detectionMethod, detection: status.detection,
            awaitsReopen: status.awaitsReopenForAudioRecording
        )
        if settingsModel.permissions != state { settingsModel.permissions = state }
    }

    /// A click on a missing permission's button, wherever it shows: macOS's
    /// own prompt when it hasn't asked yet, else System Settings; for
    /// Automation with the player closed, the player; for Audio Recording
    /// allowed in System Settings, reopening AutoHush.
    func requestPermission(_ permission: Permission) {
        Task { [weak self] in
            guard let self else { return }
            await self.refreshPermissions()
            let state = self.settingsModel.permissions
            let access: PermissionAccess = switch permission {
            case .systemAudioRecording: state.audio
            case _ where permission == state.control: state.controlAccess
            case .accessibility: state.accessibility ? .allowed : .denied
            case .automation: .denied
            }
            guard let request = PermissionCenter.request(for: permission, access: access) else { return }
            switch request {
            case .openPlayer:
                if let url = self.status.chosenPlayer?.appURL { await self.openApp(url) }
            case .reopen:
                self.reopen()
            case .openSettings, .askMacOS:
                await self.permissionCenter.perform(request, player: self.player)
                // macOS applies Audio Recording switched on there only from the next launch.
                if request == .openSettings(.audioCapture) { self.noteAudioRecordingAllowedInSettings() }
            }
            await self.refreshPermissions()
        }
    }
}
