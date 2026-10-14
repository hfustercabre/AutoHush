import AppKit
import OSLog
import AutoHushKit
import AutoHushPlayers

// AppDelegate: the player quitting and opening again.
extension AppDelegate {
    func registerPlayerLaunchObserver() {
        guard playerLaunchObserver == nil else { return }
        playerLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract the Sendable String before crossing the actor boundary.
            let bundleIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleApplicationDidLaunch(bundleIdentifier: bundleIdentifier)
            }
        }
    }

    /// A supported player opened: it is installed now. While none is chosen,
    /// the welcome window asks again; the chosen one is controlled afresh.
    func handleApplicationDidLaunch(bundleIdentifier: String?) {
        guard let bundleIdentifier, players.player(bundleID: bundleIdentifier) != nil else { return }
        refreshPlayerOptions()
        guard player != nil else {
            showPlayerChooser()
            return
        }
        session.playerLaunched(bundleIdentifier)
    }

    /// The Mac going to sleep and waking up, for the player session (see
    /// `PlayerSession.setAsleep`). The screens waking count as awake too, so
    /// a wake macOS didn't announce can't leave AutoHush deciding nothing.
    func registerSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.screensDidWakeNotification, false),
        ].map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.session.setAsleep(asleep) }
            }
        }
    }

    func unregisterPlayerLaunchObserver() {
        guard let playerLaunchObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(playerLaunchObserver)
        self.playerLaunchObserver = nil
    }
}
