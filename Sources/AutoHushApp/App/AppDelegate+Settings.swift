import AppKit
import AutoHushKit
import AutoHushPlayers

// AppDelegate: the user's settings.
extension AppDelegate {
    /// Shows Auto-Pause and the apps in the menu and the windows (Settings
    /// reads the rest from `UserSettings` itself), and passes what the
    /// monitoring follows on to the player session. The status is written
    /// once, so the menu is drawn once, never half updated (the 2026-11-06
    /// full check's K2-7).
    func showUserSettings(_ settings: UserSettings.State) {
        var shown = status
        shown.autoPause = settings.autoPause
        shown.snooze = settings.snooze
        status = withApps(shown)
        session.settings = settings.monitoring
    }

    /// Shows the ignored apps in the menu, and the apps seen and ignored in
    /// Settings → Sound Sources.
    func showApps() {
        status = withApps(status)
    }

    /// `shown` with the apps seen and ignored; never the chosen player,
    /// which doesn't pause itself, so an entry for it would do nothing.
    private func withApps(_ shown: AppStatus) -> AppStatus {
        let chosen = player?.bundleID
        let withoutPlayer = { (apps: [AudioSource]) in apps.filter { $0.id != chosen } }
        var shown = shown
        shown.seenApps = withoutPlayer(userSettings.state.seenApps)
        shown.ignoredApps = withoutPlayer(userSettings.state.ignoredApps)
        return shown
    }

    /// Ignores the apps that play only the volume sound
    /// (`SupportedPlayers.volumeSoundApps`) among those running or just
    /// opened, before they play it.
    func ignoreVolumeSoundApps(_ apps: [AudioSource]) {
        for app in apps where SupportedPlayers.volumeSoundApps.contains(app.id) {
            userSettings.ignoreByDefault(app)
        }
    }
}
