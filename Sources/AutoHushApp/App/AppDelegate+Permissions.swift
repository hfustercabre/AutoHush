import AppKit
import AutoHushKit

/// What the windows show about the permissions AutoHush needs, and a click
/// on a missing one's button (see `PermissionCenter`).
extension AppDelegate {
    /// Brings what the windows show about the permissions up to date. Two
    /// may run at once (the menu opens, a player is chosen from it): one read
    /// for a player that's no longer chosen when it's done is dropped, so a
    /// slow read never leaves the previous player's permissions shown.
    func refreshPermissions() async {
        let player = player
        let state = await permissionCenter.state(
            player: player, detectionMethod: userSettings.state.detection, detection: status.detection,
            awaitsReopen: status.awaitsReopenForAudioRecording
        )
        guard self.player?.bundleID == player?.bundleID else { return }
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
            await self.carryOut(request, app: self.player?.bundleID) {
                if let url = self.status.chosenPlayer?.appURL { await self.openApp(url) }
            }
            await self.refreshPermissions()
        }
    }

    /// Carries out `request` for the app with bundle ID `app`, wherever its
    /// button shows (Add an App's too): `openingApp` opens the app, for
    /// Automation; Audio Recording allowed in System Settings marks AutoHush
    /// as waiting to reopen.
    func carryOut(_ request: PermissionRequest, app: String?, openingApp: () async -> Void) async {
        switch request {
        case .openPlayer:
            await openingApp()
        case .reopen:
            reopen()
        case .openSettings, .askMacOS:
            await permissionCenter.perform(request, app: app)
            // macOS applies Audio Recording switched on there only from the next launch.
            if request == .openSettings(.audioCapture) { noteAudioRecordingAllowedInSettings() }
        }
    }

    /// The user went to allow Audio Recording in System Settings: macOS
    /// applies it only from the next launch, so the menu, Settings and Add
    /// an App offer to reopen.
    func noteAudioRecordingAllowedInSettings() {
        status.awaitsReopenForAudioRecording = true
    }

    /// The info button after the card's line: why the player couldn't be
    /// controlled (also in Settings → Diagnostics, as "Last error").
    func showControlError() {
        guard let alert = status.controlErrorAlert else { return }
        // Now Playing hidden in the menu bar: the pane where it's shown.
        let opens = status.controlError?.opensMenuBarSettings == true
        InfoAlert.show(alert.title, alert.message,
                       action: opens ? (ControlFailure.openMenuBarSettings, { SystemSettingsPane.menuBar.open() }) : nil,
                       run: runAlert)
    }
}
