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
            // Extract the Sendable values before crossing the actor boundary.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleIdentifier = app?.bundleIdentifier, source = app?.audioSource
            Task { @MainActor [weak self] in
                self?.ignoreVolumeSoundApps(source.map { [$0] } ?? [])
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

    /// A player found without its option again this soon after AutoHush
    /// reopened it drops the option when reopened (a launcher that starts
    /// the app again without it): it isn't reopened by itself again.
    private static let reopenAgainAfter: TimeInterval = 60

    /// Whether the chosen player runs without what it needs to be controlled
    /// wherever its window is (`MusicPlayer.needsReopen`): the card says so.
    /// `asking` (it was just chosen): an alert first offers to reopen it.
    /// One the user chose to reopen always (the alert's checkbox) is
    /// reopened at once, whenever it's found so, but at most once for each
    /// time it's opened (`reopensByItself`).
    func followPlayerReopen(asking: Bool = false) {
        guard let player else {
            status.playerNeedsReopen = false
            return
        }
        Task { [weak self] in
            let needs = await player.needsReopen()
            guard let self, self.player?.bundleID == player.bundleID else { return }
            if needs, ReopenChoices.reopensAlways(player.bundleID, defaults: self.defaults), self.reopensByItself(player) {
                self.logger.notice("\(player.name, privacy: .public) runs without the option it needs: reopening it, as the user chose")
                await self.reopen(player)
                return
            }
            if self.status.playerNeedsReopen != needs {
                self.status.playerNeedsReopen = needs
                if needs { self.logger.notice("\(player.name, privacy: .public) runs without the option it needs: it needs reopening") }
            }
            guard needs, asking else { return }
            // Not inside this task: the alert's modal loop would hold up the
            // player's state reports, the menu, a quit asked for.
            InfoAlert.whenNoneOpen {
                guard self.player?.bundleID == player.bundleID, self.status.playerNeedsReopen else { return }
                let (reopens, always) = self.askToReopen(player.name)
                if always { ReopenChoices.setReopensAlways(player.bundleID, defaults: self.defaults) }
                if reopens { Task { await self.reopen(player, tellsIfFails: true) } }
            }
        }
    }

    /// The card's Reopen button.
    func reopenChosenPlayer() {
        guard let player else { return }
        Task { [weak self] in await self?.reopen(player, tellsIfFails: true) }
    }

    /// Whether a player the user chose to reopen always, found without its
    /// option, is reopened now: not when AutoHush reopened it less than
    /// `reopenAgainAfter` ago, which would quit and reopen it over and over.
    /// Giving up is logged once, and the card says it needs reopening.
    private func reopensByItself(_ player: any MusicPlayer) -> Bool {
        guard let last = lastReopens[player.bundleID],
              clock().timeIntervalSince(last.at) < Self.reopenAgainAfter else { return true }
        if !last.gaveUp {
            lastReopens[player.bundleID]?.gaveUp = true
            logger.notice("\(player.name, privacy: .public) runs without the option it needs again right after being reopened: it isn’t reopened by itself again this time")
        }
        return false
    }

    /// `tellsIfFails`: the user asked for it (the card's Reopen, the
    /// alert's), so a reopen that fails says so; one AutoHush does by itself
    /// leaves that to the card.
    private func reopen(_ player: any MusicPlayer, tellsIfFails: Bool = false) async {
        // From the start: it opens again before the reopen is over.
        lastReopens[player.bundleID] = (clock(), false)
        let reopened = await player.reopen()
        logger.notice("\(player.name, privacy: .public) \(reopened ? "reopened with what it needs" : "couldn’t be reopened", privacy: .public)")
        if !reopened, tellsIfFails { tellFailure(PlayerAlerts.couldNotReopen(player.name)) }
        let needs = await player.needsReopen()
        if self.player?.bundleID == player.bundleID { status.playerNeedsReopen = needs }
    }

    /// The alert when a player that needs reopening is chosen: Reopen (Return)
    /// or Cancel (Escape), which leaves the card saying so; its checkbox
    /// reopens it so from then on without asking.
    private func askToReopen(_ name: String) -> (reopens: Bool, always: Bool) {
        let alert = Self.reopenAlert(name)
        let reopens = runAlert(alert) == .alertFirstButtonReturn
        return (reopens, reopens && alert.suppressionButton?.state == .on)
    }

    static func reopenAlert(_ name: String) -> NSAlert {
        let alert = PlayerAlerts.confirm(
            title: String(localized: "Reopen \(name)?",
                          comment: "Alert title when a media player added through a check was chosen while opened without an option it needs; %@ is the player"),
            message: AddAppText.reopenAlertMessage(name),
            button: AddAppText.reopenTitle(name)
        )
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = AddAppText.reopenAlways(name)
        return alert
    }

    func unregisterPlayerLaunchObserver() {
        guard let playerLaunchObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(playerLaunchObserver)
        self.playerLaunchObserver = nil
    }
}
