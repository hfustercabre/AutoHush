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
        setLearningPause(deadline: nil, note: nil, mode: .automatic)
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

    /// Learns the chosen player's controls afresh, as the user asked: once
    /// learned (they may have been learned wrong), or before (the learning
    /// window was closed halfway). A window showing the steps closes, and so
    /// does Add a Web App, and a new learning window starts from the first
    /// step. What the player
    /// learned stays until the user says it plays there; closing the window
    /// before that keeps it (`learningWindowClosed`).
    func learnControlsAgain() {
        guard let learner = player as? any LearningMusicPlayer else { return }
        logger.notice("Learning \(learner.name, privacy: .public)'s controls again, as asked")
        if let window = learningWindow, window.isOpen {
            window.onClose = nil // replaced, not left: nothing to keep
            window.close()
        }
        learningWindow = nil // a new one, not the old one's last state
        // Add a Web App floats in the same corner: it goes, an add under way
        // with it (cancelled, as its Cancel does).
        if let window = addWebAppWindow, window.isOpen { window.close() }
        learningTimer?.cancel()
        learningTimer = nil
        setLearningPause(deadline: nil, note: nil, mode: .automatic)
        Task { [weak self] in
            await learner.learnAgain()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            self.showLearningWindow()
        }
    }

    /// The user's clicks while AutoHush learns the chosen player: It's
    /// Playing, then, if AutoHush couldn't pause it itself, Try Again or
    /// Pause It Manually, and It's Paused. A click that can't be taken
    /// leaves a note under its step saying why.
    func learningStep(_ button: StepButton) {
        guard let learner = player as? any LearningMusicPlayer else { return }
        switch button {
        case .itsPlaying, .tryAgain: pauseByItself(learner)
        case .pauseManually: pauseByHand(learner)
        case .itsPaused: markPaused(learner)
        case .addToDock: break
        }
    }

    /// It plays (It's Playing, or Try Again): a fresh look at its page, then
    /// AutoHush pauses it itself and learns. When that doesn't take, its
    /// step is marked failed, offering Try Again and Pause It Manually.
    private func pauseByItself(_ learner: any LearningMusicPlayer) {
        setLearningPause(deadline: nil, note: nil, mode: .trying)
        Task { [weak self] in
            let mark = await learner.markPlaying()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            guard mark == .noted else { return await self.backToPlaying(learner, after: mark) }
            let paused = await learner.pauseByItself()
            guard self.player?.bundleID == learner.bundleID else { return }
            if !paused, learner.learningStatus == .learning(hasPlayed: true) {
                self.setLearningPause(deadline: nil, note: nil, mode: .failed)
            }
        }
    }

    /// Pause It Manually: a fresh look at its page while it plays, then the
    /// user has `learningPauseWait` to pause it and say so (It's Paused).
    private func pauseByHand(_ learner: any LearningMusicPlayer) {
        Task { [weak self] in
            let mark = await learner.markPlaying()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            guard mark == .noted else { return await self.backToPlaying(learner, after: mark) }
            self.setLearningPause(deadline: nil, note: nil, mode: .byHand)
            self.startLearningPause()
        }
    }

    /// It's Paused: learned, or a note under the step saying why not.
    private func markPaused(_ learner: any LearningMusicPlayer) {
        Task { [weak self] in
            let mark = await learner.markPaused()
            guard let self, self.player?.bundleID == learner.bundleID else { return }
            switch mark {
            case .nothingChanged: self.setLearningPause(deadline: self.settingsModel.learningPauseDeadline, note: .nothingChanged)
            case .tooLate:        self.setLearningPause(deadline: nil, note: .timedOut, mode: .automatic)
            case .cantSeePage:    self.setLearningPause(deadline: nil, note: .cantSeePage, mode: .automatic)
            case .noted, .notLearning, .notHeard: break
            }
        }
    }

    /// The look while it plays couldn't be taken (it's silent, or its page
    /// can't be read): back to the first step, saying why.
    private func backToPlaying(_ learner: any LearningMusicPlayer, after mark: LearningMark) async {
        if learner.learningStatus == .learning(hasPlayed: true) { await learner.restartLearning() }
        guard player?.bundleID == learner.bundleID else { return }
        let note: LearningNote? = switch mark {
        case .notHeard: .notHeard
        case .cantSeePage: .cantSeePage
        default: nil
        }
        setLearningPause(deadline: nil, note: note, mode: .automatic)
    }

    /// The learning window closed (Later, its close button, or learned):
    /// learning again, before the user said it plays, what the player
    /// learned stays. The player knows whether it was learning again: its
    /// status may say it learns meanwhile (its button went missing).
    private func learningWindowClosed() {
        guard let learner = player as? any LearningMusicPlayer else { return }
        Task { await learner.keepLearned() }
    }

    /// Follows learning as the player reports it. Once it plays, AutoHush
    /// pauses it, or the user does (their minute starts at Pause It
    /// Manually). Back at the first step, the note that says why stays (set
    /// by whatever sent it back); learned, the steps show how it was paused;
    /// with nothing to learn, nothing shows.
    func followLearningPause(_ learning: LearningStatus?) {
        if learning == .learning(hasPlayed: true) { return }
        learningTimer?.cancel()
        learningTimer = nil
        switch learning {
        case .learning?, .relearning?:
            setLearningPause(deadline: nil, note: settingsModel.learningNote, mode: .automatic)
        case .learned?:
            setLearningPause(deadline: nil, note: nil, mode: settingsModel.learningPauseMode == .failed ? .automatic : nil)
        case nil:
            setLearningPause(deadline: nil, note: nil, mode: .automatic)
        }
    }

    /// The user has `learningPauseWait` to pause the player and say so; the
    /// steps count it down, then learning starts over, saying why.
    private func startLearningPause() {
        learningTimer?.cancel()
        setLearningPause(deadline: Date().addingTimeInterval(Double(learningPauseWait.components.seconds)), note: nil)
        let wait = learningPauseWait
        learningTimer = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, let learner = self?.player as? any LearningMusicPlayer else { return }
            // It's Paused may have come at the last moment: learned, nothing to say.
            if await learner.restartLearning() { self?.setLearningPause(deadline: nil, note: .timedOut, mode: .automatic) }
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

    /// The window that asks to play and pause the chosen player once. As it
    /// opens, the player is opened too when it isn't running, as after adding
    /// it: the first step is to play a song there.
    func showLearningWindow() {
        let opening = learningWindow?.isOpen != true
        if learningWindow == nil { learningWindow = makeLearningWindow(settingsModel) }
        learningWindow?.onClose = { [weak self] in self?.learningWindowClosed() }
        learningWindow?.show()
        watchWindows() // follows the permission it may wait for
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
        }
    }
}
