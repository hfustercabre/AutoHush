import AppKit
import AutoHushKit

/// Learning a player AutoHush must watch once (a Safari web app), and what
/// Add a Web App needs of AutoHush (`AddWebAppFeature`).
extension AppDelegate {
    // MARK: - Learning a player

    /// Learns the chosen player's controls afresh, as the user asked: a
    /// window showing the steps closes, and so does Add a Web App, and a new
    /// learning window starts from the first step (`LearningSession`).
    func learnControlsAgain() {
        guard player is any LearningMusicPlayer else { return }
        if let window = learningWindow, window.isOpen {
            window.onClose = nil // replaced, not left: nothing to keep
            window.close()
        }
        learningWindow = nil // a new one, not the old one's last state
        // Add a Web App floats in the same corner: it goes, an add under way
        // with it (cancelled, as its Cancel does).
        addWebApp.close()
        Task { [weak self] in
            guard let self, await self.learning.learnAgain() else { return }
            self.showLearningWindow()
        }
    }

    /// The window that asks to play and pause the chosen player once. As it
    /// opens, the player is opened too when it isn't running, as after adding
    /// it: the first step is to play something there.
    func showLearningWindow() {
        let opening = learningWindow?.isOpen != true
        if learningWindow == nil { learningWindow = makeLearningWindow(settingsModel) }
        learningWindow?.onClose = { [weak self] in self?.learning.windowClosed() }
        learningWindow?.show()
        windowWatch.wake() // follows the permission it may wait for
        if opening, let player, let url = status.chosenPlayer?.appURL, !permissionCenter.isRunning(player.bundleID) {
            Task { await openApp(url) }
        }
    }
}

extension AppDelegate: AddWebAppHost {
    var chosenPlayerID: String? { player?.bundleID }
    var chosenPlayerIsLearned: Bool {
        if case .learned? = (player as? any LearningMusicPlayer)?.learningStatus { true } else { false }
    }
    var settingsForWindows: SettingsModel { settingsModel }
    func isPlayer(_ bundleID: String) -> Bool { players.player(bundleID: bundleID) != nil }
    func chooseWebApp(_ bundleID: String, showsLearningWindow: Bool) {
        chooseMusicPlayer(bundleID, showsLearningWindow: showsLearningWindow)
    }
    func requestSafariAccess() { requestPermission(AddWebAppModel.safariAccess) }
    func followWindows() { windowWatch.wake() }
}
