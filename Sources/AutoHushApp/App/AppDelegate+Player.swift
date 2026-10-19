import AppKit
import AutoHushKit

// AppDelegate: choosing and following the media player.
extension AppDelegate {
    /// Makes `bundleID` the player AutoHush controls and starts over with it.
    /// A player that isn't installed, or is chosen already, is ignored, as
    /// is one only its sound tells about while AntiDot mode is on (its tile
    /// and row are dimmed then). Music that AutoHush holds paused in the
    /// previous player stays paused: the user is moving to another one. A
    /// player AutoHush must learn opens the learning window, unless another
    /// window shows the steps. A suggested web app opens "Add a Web App",
    /// filled in with its address.
    /// `replacing`: chosen again all the same, as an app checked again
    /// (its new setup); `asksToReopen`: false right after the user skipped
    /// reopening it in Add an App.
    func chooseMusicPlayer(_ bundleID: String, showsLearningWindow: Bool = true, replacing: Bool = false,
                           asksToReopen: Bool = true) {
        refreshPlayerOptions()
        let option = status.playerOptions.first { $0.bundleID == bundleID }
        if let address = option?.webAddress {
            showAddWebApp(address: address)
            return
        }
        guard bundleID != player?.bundleID || replacing,
              let chosen = players.player(bundleID: bundleID),
              let appURL = option?.appURL
        else { return }
        // AntiDot mode hears no sound, so it can't tell how this one is.
        if chosen.needsAudioLevels, userSettings.state.detection != .audioLevels {
            logger.notice("\(chosen.name, privacy: .public) isn’t chosen: only its sound tells how it is, and AntiDot mode doesn’t hear it")
            return
        }
        logger.notice("Media player chosen: \(chosen.name, privacy: .public)")
        setChosenPlayer(chosen)
        watchFolders(holding: appURL)
        showApps()
        // From the welcome window: it goes on to what the player needs, and
        // closes once that's allowed; the learning window waits for it.
        let fromWelcome = isShowingPlayerChooser
        if fromWelcome { settingsModel.welcomeAsksPermissions = true }
        learningAfterWelcome = false
        if showsLearningWindow, case .learning = (chosen as? any LearningMusicPlayer)?.learningStatus {
            if fromWelcome { learningAfterWelcome = true } else { showLearningWindow() }
        }
        if fromWelcome { windowWatch.wake() }
        followPlayerReopen(asking: asksToReopen)
    }

    /// The welcome window is done: the player is chosen and what it needs
    /// allowed (or the window was closed). A player to learn opens the
    /// learning window then.
    func finishWelcome() {
        settingsModel.welcomeAsksPermissions = false
        if isShowingPlayerChooser { playerChooser?.close() }
        guard learningAfterWelcome else { return }
        learningAfterWelcome = false
        if case .learning = status.learning { showLearningWindow() }
    }

    /// Shows how learning goes: whether it's learned in the menu and
    /// Settings, the steps and the pause in their windows; once learned, or
    /// with nothing to learn, the windows that show the steps close.
    func showLearning(_ state: LearningSession.State) {
        let learningStatus = state.status
        let changed = learningStatus != status.learning
        var shown = status
        shown.learning = learningStatus
        shown.learningPause = state.pause
        status = shown
        guard changed, learningStatus == nil || learningStatus == .learned else { return }
        // Learned (both steps ticked), or nothing to learn: the windows go.
        let delay = learningStatus == .learned ? learnedWindowDelay : .zero
        if let window = learningWindow, window.isOpen {
            closeLater(after: delay, ifStill: learningStatus) { window.close() }
        }
        if let window = addWebAppWindow, window.isOpen, case .learning = addWebAppModel.phase {
            closeLater(after: delay, ifStill: learningStatus) { window.close() }
        }
    }

    /// Closes a window that shows the learning steps once `delay` is over,
    /// if learning is still at `learningStatus` then.
    private func closeLater(after delay: Duration, ifStill learningStatus: LearningStatus?,
                            _ close: @escaping @MainActor () -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.status.learning == learningStatus else { return }
            close()
        }
    }

    /// Shows the chosen player in the menu and the windows: its traits
    /// (muted instead of paused, fades) come with its option.
    func showChosenPlayer() {
        status.chosenPlayerID = player?.bundleID
    }

    /// Checks again which players are installed, for the menu, Settings and
    /// the welcome window. While none is chosen, the status line follows. The
    /// chosen player is reported as soon as it's uninstalled, as a launch
    /// would, and controlled afresh once it's installed again.
    func refreshPlayerOptions() {
        let options = PlayerOption.list(players, locate: locateApp)
        status.playerOptions = options
        forgetDeletedWebApps(among: options)
        pickUpListedWebApp(among: options)
        guard let player else {
            showSession() // waiting for a player, among these
            return
        }
        // A deleted web app can't come back as the same app (adding the site
        // again makes a new one): no player is chosen any more, and the
        // welcome window asks for one, as when the chosen app is removed.
        if player.kind == .safariWebApp, !options.contains(where: { $0.bundleID == player.bundleID }),
           Self.isDeleted(player.bundleID) {
            logger.notice("\(player.name, privacy: .public) was deleted: no media player is chosen")
            setChosenPlayer(nil)
            showPlayerChooser()
            return
        }
        let appURL = options.first { $0.bundleID == player.bundleID }?.appURL
        watchFolders(holding: appURL)
        session.setPlayerInstalled(appURL != nil)
    }

    /// Watches the Applications folders, and the folder the chosen player's
    /// app is in when it's one inside them. A folder that can't be watched
    /// yet (no ~/Applications) is tried again at the next check.
    private func watchFolders(holding appURL: URL?) {
        var paths = Set(ApplicationFolders.all.map(\.path))
        if let appURL { paths.insert(appURL.deletingLastPathComponent().path) }
        for path in folderWatches.keys where !paths.contains(path) {
            folderWatches[path] = nil
        }
        for path in paths where folderWatches[path] == nil {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            guard let watch = watchFolder(folder, { [weak self] in self?.checkInstalledPlayersSoon() }) else { continue }
            folderWatches[path] = watch
            logger.debug("Watching \(path, privacy: .public) for installed music players")
        }
    }

    /// Whether the app is deleted: macOS doesn't know it, or only in the Trash.
    private static func isDeleted(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return true }
        return url.pathComponents.contains(".Trash")
    }

    /// `player` is the chosen one now (`nil`: none, and the status line asks
    /// for one): it's stored, and the player session and the learning
    /// session are told together, so they always follow the same player.
    func setChosenPlayer(_ player: (any MusicPlayer)?) {
        preferences.musicPlayer = player?.bundleID
        session.choose(player)
        showChosenPlayer()
        learning.follow(player)
    }

    /// Forgets the learned buttons of web apps that are gone: deleted, not
    /// just moved (macOS still knows those, the Trash included). Adding a site
    /// again makes a new web app, with a new ID.
    private func forgetDeletedWebApps(among options: [PlayerOption]) {
        let installed = Set(options.filter { $0.kind == .safariWebApp && $0.isInstalled }.map(\.bundleID))
        preferences.forgetWebAppButtons { id in
            !installed.contains(id) && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil
        }
    }

    /// Checks the players again once a change in a watched folder settles
    /// (a move, an update swapping the app) and Launch Services catches up;
    /// a later change starts the wait over.
    private func checkInstalledPlayersSoon() {
        installCheck?.cancel()
        installCheck = Task { [weak self, installCheckDelay] in
            try? await Task.sleep(for: installCheckDelay)
            guard !Task.isCancelled else { return }
            self?.refreshPlayerOptions()
        }
    }

    /// The welcome window, which asks for the media player.
    func showPlayerChooser() {
        if playerChooser == nil {
            playerChooser = makePlayerChooser(settingsModel)
        }
        settingsModel.welcomeAsksPermissions = false
        refreshPlayerOptions()
        playerChooser?.show()
        windowWatch.wake()
    }

    /// The menu opens: what it lists is brought up to date. The welcome
    /// window, still open, comes forward to the desktop the user is on:
    /// another app may have covered it, or taken the user to another desktop,
    /// since it opened.
    func menuWillOpen() {
        refreshPlayerOptions()
        followPlayerReopen()
        session.checkAccess()
        // The card's checks say which permission is allowed: as it is now.
        Task { [weak self] in await self?.refreshPermissions() }
        if isShowingPlayerChooser { playerChooser?.bringForward() }
    }

    /// Whether the welcome window is on screen.
    var isShowingPlayerChooser: Bool { playerChooser?.isOpen == true }
}
