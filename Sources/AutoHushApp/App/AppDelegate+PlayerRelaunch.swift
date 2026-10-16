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

    /// A player found without its option again this soon after AutoHush
    /// reopened it drops the option when reopened (a launcher that starts
    /// the app again without it): it isn't reopened by itself again.
    private static let reopenAgainAfter: TimeInterval = 60

    /// When AutoHush last reopened each player, by bundle ID, and whether it
    /// then gave up reopening it by itself (`reopensByItself`).
    private static var lastReopens: [String: (at: Date, gaveUp: Bool)] = [:]
    /// The clock `lastReopens` is stamped and read by. Tests move it on.
    static var now: () -> Date = Date.init

    /// Runs the reopen alert and returns the button pressed. Tests replace it.
    static var runReopenAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = InfoAlert.runInFront

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
            if needs, ReopenChoices.reopensAlways(player.bundleID), self.reopensByItself(player) {
                self.logger.notice("\(player.name, privacy: .public) runs without the option it needs: reopening it, as the user chose")
                await self.reopen(player)
                return
            }
            if self.status.playerNeedsReopen != needs {
                self.status.playerNeedsReopen = needs
                if needs { self.logger.notice("\(player.name, privacy: .public) runs without the option it needs: it needs reopening") }
            }
            guard needs, asking else { return }
            // From the run loop: run inside this task, the alert's modal loop
            // would hold up every other main-actor job until it closes (the
            // player's state reports, the menu, a quit asked for).
            RunLoop.main.perform(inModes: [.common]) {
                MainActor.assumeIsolated {
                    guard self.player?.bundleID == player.bundleID, self.status.playerNeedsReopen else { return }
                    let (reopens, always) = Self.askToReopen(player.name)
                    if always { ReopenChoices.setReopensAlways(player.bundleID) }
                    if reopens { Task { await self.reopen(player) } }
                }
            }
        }
    }

    /// The card's Reopen button.
    func reopenChosenPlayer() {
        guard let player else { return }
        Task { [weak self] in await self?.reopen(player) }
    }

    /// Whether a player the user chose to reopen always, found without its
    /// option, is reopened now: not when AutoHush reopened it less than
    /// `reopenAgainAfter` ago, which would quit and reopen it over and over.
    /// Giving up is logged once, and the card says it needs reopening.
    private func reopensByItself(_ player: any MusicPlayer) -> Bool {
        guard let last = Self.lastReopens[player.bundleID],
              Self.now().timeIntervalSince(last.at) < Self.reopenAgainAfter else { return true }
        if !last.gaveUp {
            Self.lastReopens[player.bundleID]?.gaveUp = true
            logger.notice("\(player.name, privacy: .public) runs without the option it needs again right after being reopened: it isn’t reopened by itself again this time")
        }
        return false
    }

    private func reopen(_ player: any MusicPlayer) async {
        // From the start: it opens again before the reopen is over.
        Self.lastReopens[player.bundleID] = (Self.now(), false)
        let reopened = await player.reopen()
        logger.notice("\(player.name, privacy: .public) \(reopened ? "reopened with what it needs" : "couldn’t be reopened", privacy: .public)")
        let needs = await player.needsReopen()
        if self.player?.bundleID == player.bundleID { status.playerNeedsReopen = needs }
    }

    /// The alert when a player that needs reopening is chosen: Reopen (Return)
    /// or Cancel (Escape), which leaves the card saying so; its checkbox
    /// reopens it so from then on without asking.
    private static func askToReopen(_ name: String) -> (reopens: Bool, always: Bool) {
        let alert = reopenAlert(name)
        let reopens = runReopenAlert(alert) == .alertFirstButtonReturn
        return (reopens, reopens && alert.suppressionButton?.state == .on)
    }

    static func reopenAlert(_ name: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reopen \(name)?",
                                   comment: "Alert title when a media player added through a check was chosen while opened without an option it needs; %@ is the player")
        alert.informativeText = AddAppText.reopenAlertMessage(name)
        alert.alertStyle = .warning
        alert.addButton(withTitle: AddAppText.reopenTitle(name))
        alert.addButton(withTitle: AddAppText.cancel).keyEquivalent = "\u{1b}" // Escape; Return reopens
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = AddAppText.reopenAlways(name)
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
