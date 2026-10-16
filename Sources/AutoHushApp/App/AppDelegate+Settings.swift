import AppKit
import AutoHushKit

// AppDelegate: the user's settings and the updates' settings.
extension AppDelegate {
    /// Shows Auto-Pause and the apps in the menu and the windows (Settings
    /// reads the rest from `UserSettings` itself), and passes what the
    /// monitoring follows on to the player session.
    func showUserSettings(_ settings: UserSettings.State) {
        status.autoPause = settings.autoPause
        showApps()
        session.settings = settings.monitoring
    }

    /// Shows the ignored apps in the menu, and the apps seen and ignored in
    /// Settings → Apps; never the chosen player, which doesn't pause itself,
    /// so an entry for it would do nothing.
    func showApps() {
        let chosen = player?.bundleID
        let withoutPlayer = { (apps: [AudioSource]) in apps.filter { $0.id != chosen } }
        var shown = status
        shown.seenApps = withoutPlayer(userSettings.state.seenApps)
        shown.ignoredApps = withoutPlayer(userSettings.state.ignoredApps)
        status = shown
    }

    /// Shows how a check from Settings is going, and when updates were last
    /// checked for (every check reports here).
    func showUpdateStatus(_ status: String) {
        settingsModel.updateStatus = status
        settingsModel.lastUpdateCheck = preferences.lastUpdateCheck
    }

    /// Shows the update settings as they are, after the user or AutoHush
    /// changed them.
    func showUpdateSettings() {
        settingsModel.checksForUpdatesAutomatically = updates.checksAutomatically
        settingsModel.automaticUpdates = updates.mode
    }
}
