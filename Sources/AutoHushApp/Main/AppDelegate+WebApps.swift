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
        // Another player: nothing it was told carries over.
        learningTimer?.cancel()
        learningTimer = nil
        setLearningPause(deadline: nil, note: nil)
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

    /// Forgets the chosen player's learned controls and learns them again,
    /// as the user asked (they may have been learned wrong): the learning
    /// window shows the steps, as the first time. Nothing while it's
    /// learning already.
    func learnControlsAgain() {
        guard let learner = player as? any LearningMusicPlayer, learner.learningStatus == .learned else { return }
        logger.notice("Learning \(learner.name, privacy: .public)'s controls again, as asked")
        Task { [weak self] in
            await learner.learnAgain()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            self.showLearningWindow()
        }
    }

    /// The user says, while AutoHush learns the chosen player, that it plays
    /// (It's Playing) or that they paused it (It's Paused). A click that
    /// can't be taken leaves a note under its step saying why.
    func learningStep(_ button: StepButton) {
        guard button != .addToDock, let learner = player as? any LearningMusicPlayer else { return }
        Task { [weak self] in
            let mark = button == .itsPlaying ? await learner.markPlaying() : await learner.markPaused()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            switch mark {
            case .notHeard:       self.setLearningPause(deadline: self.status.learningPauseDeadline, note: .notHeard)
            case .nothingChanged: self.setLearningPause(deadline: self.status.learningPauseDeadline, note: .nothingChanged)
            case .tooLate:        self.setLearningPause(deadline: nil, note: .timedOut)
            case .cantSeePage:    self.setLearningPause(deadline: nil, note: .cantSeePage)
            case .noted, .notLearning: break
            }
        }
    }

    /// Once the user said the player plays, they have `learningPauseWait` to
    /// pause it and say so; the steps count it down, then learning starts
    /// over, saying why. Back at the first step, the note that says why stays
    /// (set by whatever sent it back); learned, or nothing to learn, none.
    func followLearningPause(_ learning: LearningStatus?) {
        if learning == .learning(hasPlayed: true) {
            guard learningTimer == nil else { return }
            setLearningPause(deadline: Date().addingTimeInterval(Double(learningPauseWait.components.seconds)), note: nil)
            let wait = learningPauseWait
            learningTimer = Task { [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let learner = self?.player as? any LearningMusicPlayer else { return }
                // It's Paused may have come at the last moment: learned, nothing to say.
                if await learner.restartLearning() { self?.setLearningPause(deadline: nil, note: .timedOut) }
            }
            return
        }
        learningTimer?.cancel()
        learningTimer = nil
        setLearningPause(deadline: nil, note: learning == .learning(hasPlayed: false) ? status.learningNote : nil)
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
    /// window show the learning (or, added while the welcome window shows,
    /// closes: the welcome window goes on). Closing the window cancels it until the
    /// web app is made.
    func addWebApp(from address: String) {
        guard addingWebApp == nil else { return }
        let model = addWebAppModel
        let maker = webAppMaker
        model.attempt += 1
        let attempt = model.attempt
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
                    await model.waitForAdd()
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
                self.chooseMusicPlayer(made.bundleID, showsLearningWindow: fromWelcome)
                guard self.player?.bundleID == made.bundleID else {
                    self.logger.error("\(made.name, privacy: .public) was made but can't be chosen: it isn't found as installed")
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
