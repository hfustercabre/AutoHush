import AppKit
import AutoHushKit

/// Learning a player AutoHush must watch once (a Safari web app), and making
/// a web app from an address ("Add a Web App…").
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
        if let window = addWebAppWindow, window.isOpen { window.close() }
        Task { [weak self] in
            guard let self, await self.learning.learnAgain() else { return }
            self.showLearningWindow()
        }
    }

    // MARK: - Adding a web app

    /// The "Add a Web App" window, ready for an address, filled in with
    /// `address` if there's one (or showing the one being added).
    func showAddWebApp(address: String? = nil) {
        if addWebAppWindow == nil { addWebAppWindow = makeAddWebAppWindow(addWebAppModel, settingsModel) }
        if addingWebApp == nil, address != nil || addWebAppWindow?.isOpen != true {
            addWebAppModel.reset(address: address ?? "")
        }
        addWebAppWindow?.show()
        windowWatch.wake() // follows Accessibility, which adding needs
    }

    /// Makes the address a web app, then opens it, chooses it, and lets the
    /// window show the learning (or, added while the welcome window shows,
    /// closes: the welcome window goes on). Closing the window cancels it
    /// until the web app is made.
    func addWebApp(from address: String) {
        guard addingWebApp == nil else { return }
        webAppAwaitingListing = nil
        let model = addWebAppModel
        let maker = webAppMaker
        model.attempt += 1
        let attempt = model.attempt
        // Another player chosen while it's added (the user's, from the menu) stays.
        let before = player?.bundleID
        addingWebApp = Task { [weak self] in
            defer { if model.attempt == attempt { self?.addingWebApp = nil } }
            do {
                let made = try await maker.makeWebApp(from: address, onStep: { step in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard model.attempt == attempt else { return } // cancelled since
                            model.apply(step)
                        }
                    }
                }, confirmAdd: {
                    // The user clicks Add to Dock once the site shows.
                    await model.waitForAdd(attempt: attempt)
                })
                guard let self, model.attempt == attempt, !Task.isCancelled else { return }
                model.apply(.made(made))
                self.logger.notice("Web app ready: \(made.name, privacy: .public)\(made.alreadyThere ? " (already there)" : "", privacy: .public)")
                // Opened first, so it's running by the time it's chosen.
                await self.openApp(made.url)
                // Added while the welcome window shows (from it, or from the
                // menu meanwhile): that one asks for what the web app needs,
                // and the learning window follows its Done, as for a web app
                // picked there; this window's work is done.
                let fromWelcome = self.isShowingPlayerChooser
                guard self.player?.bundleID == before else { return }
                self.chooseMusicPlayer(made.bundleID, showsLearningWindow: fromWelcome)
                // macOS may list a new web app a little later: looked for again
                // for a few seconds, then the window says so.
                var lookups = 0
                while self.player?.bundleID == before, before != made.bundleID, lookups < Self.madeWebAppLookups,
                      model.attempt == attempt, !Task.isCancelled {
                    lookups += 1
                    try? await Task.sleep(for: self.madeWebAppWait)
                    guard self.player?.bundleID == before else { break }
                    self.chooseMusicPlayer(made.bundleID, showsLearningWindow: fromWelcome)
                }
                guard model.attempt == attempt, !Task.isCancelled else { return }
                guard self.player?.bundleID == made.bundleID else {
                    guard self.player?.bundleID == before else { return } // the user chose another one
                    self.logger.error("\(made.name, privacy: .public) was made but can't be chosen: it isn't found as installed")
                    model.fail(.notFound(name: made.name))
                    // Picked up by itself once it's listed (`pickUpListedWebApp`).
                    self.webAppAwaitingListing = (made.bundleID, address)
                    self.windowWatch.wake()
                    return
                }
                if fromWelcome {
                    self.addWebAppWindow?.close()
                    return
                }
                // Chosen and learned already: there's nothing left to show.
                if case .learned? = (self.player as? any LearningMusicPlayer)?.learningStatus {
                    try? await Task.sleep(for: self.learnedWindowDelay)
                    if case .learning = model.phase { self.addWebAppWindow?.close() }
                }
            } catch is CancellationError {
                // Logged when it was cancelled.
            } catch {
                guard model.attempt == attempt else { return }
                let failure = error as? WebAppMakingError ?? .browserFailed(error.localizedDescription)
                self?.logger.error("Couldn't add a web app: \(failure.kind, privacy: .public) (\(String(describing: failure), privacy: .private))")
                model.fail(failure)
            }
        }
    }

    /// How many times a web app just made is looked for again, `madeWebAppWait`
    /// apart, before the window says it can't be found.
    static let madeWebAppLookups = 10

    /// The web app made but not found as installed, while the add window
    /// says so: once it's listed (the window watch checks the players each
    /// second meanwhile), it's added again as it stands, which chooses it,
    /// without waiting for Continue. Not once the address was changed.
    func pickUpListedWebApp(among options: [PlayerOption]) {
        guard let awaiting = webAppAwaitingListing else { return }
        guard case .notFound? = addWebAppModel.problem, addWebAppModel.phase == .entering,
              addWebAppModel.address == awaiting.address, addWebAppWindow?.isOpen == true else {
            webAppAwaitingListing = nil
            return
        }
        guard players.player(bundleID: awaiting.bundleID) != nil,
              options.contains(where: { $0.bundleID == awaiting.bundleID && $0.isInstalled }) else { return }
        webAppAwaitingListing = nil
        logger.notice("The web app made is listed now: adding it again")
        addWebAppModel.continueTapped()
    }

    /// Stops the add under way; a step it reports later is ignored.
    func cancelAddingWebApp() {
        guard let task = addingWebApp else { return }
        logger.notice("Adding a web app was cancelled")
        task.cancel()
        addingWebApp = nil
        addWebAppModel.attempt += 1
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

private extension WebAppMakingError {
    /// What went wrong, without the address, for the log: what the user
    /// typed stays private there.
    var kind: String {
        switch self {
        case .notAWebAddress: "not a web address"
        case .noAnswer: "the site didn't answer"
        case .pageNotFound: "the page doesn't exist"
        case .accessibilityDenied: "no Accessibility permission"
        case .browserFailed: "Safari didn't do it"
        case .notFound: "the web app isn't found as installed"
        }
    }
}
