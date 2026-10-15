import AppKit
import AutoHushKit

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
        if bundleIdentifier == player?.bundleID { followPlayerReopen() }
    }

    // MARK: - A player opened without what it needs

    /// Whether the chosen player runs without what it needs to be controlled
    /// wherever its window is (`MusicPlayer.needsReopen`): the card says so.
    /// `asking` (it was just chosen): an alert first offers to reopen it.
    func followPlayerReopen(asking: Bool = false) {
        guard let player else {
            status.playerNeedsReopen = false
            return
        }
        Task { [weak self] in
            let needs = await player.needsReopen()
            guard let self, self.player?.bundleID == player.bundleID else { return }
            if needs, asking, Self.askToReopen(player.name) {
                await self.reopen(player)
            } else if self.status.playerNeedsReopen != needs {
                self.status.playerNeedsReopen = needs
                if needs { self.logger.notice("\(player.name, privacy: .public) runs without the option it needs: it needs reopening") }
            }
        }
    }

    /// The card's Reopen button.
    func reopenChosenPlayer() {
        guard let player else { return }
        Task { [weak self] in await self?.reopen(player) }
    }

    private func reopen(_ player: any MusicPlayer) async {
        let reopened = await player.reopen()
        logger.notice("\(player.name, privacy: .public) \(reopened ? "reopened with what it needs" : "couldn't be reopened", privacy: .public)")
        let needs = await player.needsReopen()
        if self.player?.bundleID == player.bundleID { status.playerNeedsReopen = needs }
    }

    /// The alert when a player that needs reopening is chosen: Reopen (Return)
    /// or Cancel (Escape), which leaves the card saying so.
    private static func askToReopen(_ name: String) -> Bool {
        let alert = reopenAlert(name)
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func reopenAlert(_ name: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reopen \(name)?",
                                   comment: "Alert title when a media player added through a check was chosen while opened without an option it needs; %@ is the player")
        alert.informativeText = AddAppText.reopenReason(name) + " " + AddAppText.reopenStops
        alert.alertStyle = .warning
        alert.addButton(withTitle: AddAppText.reopenTitle(name))
        alert.addButton(withTitle: AddAppText.cancel)
        return alert
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
