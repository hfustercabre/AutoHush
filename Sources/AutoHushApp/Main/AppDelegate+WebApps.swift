import AppKit
import AutoHushKit

/// Learning a player AutoHush must watch once (a Safari web app), and making
/// a web app from an address ("Add a Web App…").
extension AppDelegate {
    // MARK: - Learning a player

    /// Shows how learning the chosen player goes, as it goes; nothing for a
    /// player that needs no learning.
    func watchLearning() {
        learningWatch?.cancel()
        learningWatch = nil
        guard let learner = player as? any LearningMusicPlayer else {
            showLearning(nil)
            return
        }
        showLearning(learner.learningStatus)
        learningWatch = Task { [weak self] in
            for await learning in learner.learningUpdates() {
                guard !Task.isCancelled else { return }
                self?.showLearning(learning)
            }
        }
    }

    // MARK: - Adding a web app

    /// The "Add a Web App" window, ready for an address, filled in with
    /// `address` if there's one (or showing the one being added).
    func showAddWebApp(address: String? = nil) {
        if addWebAppWindow == nil { addWebAppWindow = makeAddWebAppWindow(addWebAppModel, settingsModel) }
        if addingWebApp == nil, address != nil || addWebAppWindow?.isVisible != true {
            addWebAppModel.reset(address: address ?? "")
        }
        addWebAppWindow?.show()
        watchWindows() // follows Accessibility, which adding needs
    }

    /// Makes the address a web app, then opens it, chooses it, and lets the
    /// window show the learning. Closing the window cancels it until the web
    /// app is made.
    func addWebApp(from address: String) {
        guard addingWebApp == nil else { return }
        let model = addWebAppModel
        let maker = webAppMaker
        model.attempt += 1
        let attempt = model.attempt
        addingWebApp = Task { [weak self] in
            defer { if model.attempt == attempt { self?.addingWebApp = nil } }
            do {
                let made = try await maker.makeWebApp(from: address) { step in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            guard model.attempt == attempt else { return } // cancelled since
                            model.apply(step)
                        }
                    }
                }
                guard let self, model.attempt == attempt, !Task.isCancelled else { return }
                model.apply(.made(made))
                self.logger.notice("Web app ready: \(made.name, privacy: .public)\(made.alreadyThere ? " (already there)" : "", privacy: .public)")
                // Opened first, so it's running by the time it's chosen.
                await self.openApp(made.url)
                self.chooseMusicPlayer(made.bundleID, showsLearningWindow: false)
                guard self.player?.bundleID == made.bundleID else {
                    self.logger.error("\(made.name, privacy: .public) was made but can't be chosen: it isn't found as installed")
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

    /// Stops the add under way; a step it reports later is ignored.
    func cancelAddingWebApp() {
        guard let task = addingWebApp else { return }
        logger.notice("Adding a web app was cancelled")
        task.cancel()
        addingWebApp = nil
        addWebAppModel.attempt += 1
    }

    /// The window that asks to play and pause the chosen player once.
    func showLearningWindow() {
        if learningWindow == nil { learningWindow = makeLearningWindow(settingsModel) }
        learningWindow?.show()
        watchWindows() // follows the permission it may wait for
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
        }
    }
}
