import AppKit
import OSLog
import AutoHushKit
import AutoHushPlayers

// AppDelegate: what the menu's items do.
extension AppDelegate {
    func openSettings(page: SettingsWindowController.Page? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show(page: page)
        refreshPlayerOptions()
        windowWatch.wake()
    }

    /// What each window shows that the window watch follows while it's open
    /// (Settings counts as open minimized too). macOS doesn't announce a
    /// change to these: notifications turned on or off, or reset, in System
    /// Settings (a reset is asked about again), a permission allowed (a
    /// window waiting for one goes on by itself), and the players installed
    /// while none is chosen (once one is, the folder watch follows them:
    /// `refreshPlayerOptions`).
    func registerWatchedWindows() {
        windowWatch.register(isOpen: { [weak self] in self?.settingsWindowController?.window?.isOpen == true }) { [weak self] in
            var needs: Set<WindowWatch.Refresh> = [.notifications, .launchAtLogin, .permissions]
            if self?.settingsWindowController?.shownPage == .diagnostics { needs.insert(.diagnostics) }
            if self?.player == nil { needs.insert(.players) }
            return needs
        }
        windowWatch.register(isOpen: { [weak self] in self?.isShowingPlayerChooser == true }) { [weak self] in
            self?.player == nil ? [.players, .notifications, .permissions] : [.notifications, .permissions]
        }
        windowWatch.register(isOpen: { [weak self] in self?.learningWindow?.isOpen == true }) { [.permissions] }
        windowWatch.register(isOpen: { [weak self] in self?.addWebAppWindow?.isOpen == true }) { [.permissions] }
    }

    /// One of the window watch's refreshes.
    func refresh(_ need: WindowWatch.Refresh) async {
        switch need {
        case .players:
            refreshPlayerOptions()
        case .diagnostics:
            refreshDiagnostics()
        case .notifications:
            let off = await updates.followNotificationPermission() == .off
            if settingsModel.notificationsOff != off { settingsModel.notificationsOff = off }
        case .launchAtLogin:
            settingsModel.refreshLaunchAtLogin()
        case .permissions:
            await refreshPermissions()
        }
    }

    /// The welcome window closed while it asked for the permissions: done,
    /// as with its Done button.
    func followWelcomeClosed() {
        if settingsModel.welcomeAsksPermissions, !isShowingPlayerChooser { finishWelcome() }
    }
}
