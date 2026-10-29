import Foundation
import CheckedPlayers
import PlayerCheckKit

// AddAppModel: the window opening and closing, and the steps that choose the
// app, reopen it and wait for it to play.
extension AddAppModel {
    /// Ready for an app, from the first step; the apps read again. A check
    /// that finished and wasn't used yet comes back where it ended.
    func reset() {
        windowIsOpen = true
        resetSteps()
        search = ""
        if let kept = keptChecks.load(now: now()), reader.appExists(at: kept.app.url) {
            restore(kept)
        }
        Task { await loadApps() }
    }

    /// Back to the first step, the apps as they were read.
    private func resetSteps() {
        stopWork()
        stopRun()
        stage = .choosing
        chosen = nil
        traits = nil
        permissions = CheckPermissions()
        needsReopen = false
        reopenOutcome = nil
        reopenFailed = false
        openFailed = false
        permissionMissingInCheck = false
        accessibilityNeedsReopen = false
        otherAppProblem = nil
        appQuit = false
        appNotFound = false
        failureReason = nil
        progress = CheckProgress()
        isStopping = false
        resultBeforeCheckAgain = nil
        waitsForWindow = false
        windowMissing = false
    }

    /// The check's result as it was kept: its app chosen, the last step.
    func restore(_ kept: KeptCheck) {
        chosen = kept.app
        selectedID = kept.app.id
        let traits = reader.traits(ofAppAt: kept.app.url)
        self.traits = traits
        needsReopen = kept.needsReopen
        reopenOutcome = kept.reopenOutcome
        resultBeforeCheckAgain = nil
        waitsForWindow = false
        stage = .done(kept.result)
        Task { [weak self] in await self?.refreshPermissions(for: kept.app, scriptable: traits.scriptable) }
    }

    /// The first step's button: the window that lists the apps.
    func openChooser() {
        guard stage == .choosing else { return }
        search = ""
        presenter?.showChooser()
    }

    /// Chooses `app` (from the list, or picked on the disk) and goes on.
    func choose(_ app: CheckableApp) {
        guard stage == .choosing else { return }
        if !apps.contains(where: { $0.id == app.id }) { apps.append(app) }
        selectedID = app.id
        otherAppProblem = nil
        presenter?.closeChooser()
        continueWithApp()
    }

    /// Other App…'s pick: chosen, or why it can't be.
    func chooseOther(at url: URL) {
        switch reader.app(at: url) {
        case .success(let app): choose(app)
        case .failure(let problem): otherAppProblem = problem
        }
    }

    /// Change… forgets a check that has run (about 3 minutes), so it asks
    /// first: also the one Back to Result can bring back after Check Again.
    var changeAppForgetsCheck: Bool { result != nil || resultBeforeCheckAgain != nil }

    /// The first step's Change…: from the first step again, its list open.
    /// A kept result is forgotten.
    func changeApp() {
        guard canChangeApp else { return }
        keptChecks.forget()
        presenter?.closeWarning() // its Start was for the app before
        resetSteps()
        search = ""
        presenter?.showChooser()
    }

    func loadApps() async {
        isLoadingApps = true
        apps = await reader.listApps()
        isLoadingApps = false
        if !apps.contains(where: { $0.id == selectedID }) {
            selectedID = (apps.first { $0.nowPlaying == true } ?? (apps.count(where: { $0.nowPlaying != nil }) == 1 ? apps.first : nil))?.id
        }
    }

    /// Step 1's Continue: opens the chosen app if it isn't open (with its
    /// launch option, if it needs one), then asks for what the check needs.
    func continueWithApp() {
        guard canContinueWithApp, let app = apps.first(where: { $0.id == selectedID }) else { return }
        chosen = app
        let traits = reader.traits(ofAppAt: app.url)
        self.traits = traits
        openFailed = false
        appQuit = false
        stage = .opening
        work = Task { [weak self] in
            guard let self else { return }
            if !self.reader.isRunning(app.bundleID) {
                guard await self.reader.open(app, withLaunchOption: traits.needsLaunchOption), !Task.isCancelled else {
                    if !Task.isCancelled {
                        self.openFailed = true
                        self.stage = .choosing
                    }
                    return
                }
            } else if traits.needsLaunchOption {
                self.needsReopen = await self.helper?.runsWithLaunchOption(app) == false
            }
            guard !Task.isCancelled else { return }
            self.stage = .allowing
            self.watchPermissions()
        }
    }

    /// The Reopen step's button: quits the app and opens it again with its
    /// launch option (whatever it plays stops).
    func reopen() {
        guard stage == .reopenAsked, let app = chosen else { return }
        reopenFailed = false
        stage = .reopening
        work = Task { [weak self] in
            guard let self else { return }
            let reopened = await self.helper?.reopenWithLaunchOption(app) ?? false
            guard !Task.isCancelled else { return }
            if reopened {
                self.reopenOutcome = .reopened
                self.waitForPlaying()
            } else {
                self.reopenFailed = true
                self.stage = .reopenAsked
            }
        }
    }

    /// Goes on without reopening it: its page may not take presses while
    /// it's covered or on another desktop.
    func skipReopen() {
        guard stage == .reopenAsked else { return }
        reopenOutcome = .skipped
        waitForPlaying()
    }

    /// Waits for the chosen app to play, up to `playWait`; it quitting ends
    /// the wait (`appQuit`).
    func waitForPlaying() {
        guard let app = chosen, let traits else { return }
        let since = now()
        appQuit = false
        appNotFound = false
        failureReason = nil
        windowMissing = false
        stage = .waitingToPlay(since: since)
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .waitingToPlay(since: since) {
                if !self.reader.isRunning(app.bundleID) {
                    self.quit(app)
                    return
                }
                // After Check Again with its windows closed: a window first.
                let windowOpen = self.waitsForWindow ? await self.reader.hasWindowWithinReach(app) : true
                guard self.stage == .waitingToPlay(since: since) else { return }
                self.windowMissing = !windowOpen
                if windowOpen, await self.reader.isPlaying(app, traits: traits), self.stage == .waitingToPlay(since: since) {
                    self.stage = .ready
                    return
                }
                if self.now().timeIntervalSince(since) >= Self.playWait {
                    self.stage = .playTimedOut
                    return
                }
                await self.sleep(.milliseconds(500))
            }
        }
    }

    /// Opens the app again after it quit, then waits for it to play.
    func openAppAgain() {
        guard let app = chosen, let traits, !appNotFound else { return }
        appQuit = false
        stage = .openingAgain
        work = Task { [weak self] in
            guard let self else { return }
            let opened = await self.reader.open(app, withLaunchOption: traits.needsLaunchOption)
            guard !Task.isCancelled else { return }
            if opened {
                self.waitForPlaying()
            } else {
                self.quit(app)
            }
        }
    }

    /// The app quit while it was waited for (or didn't open again): the
    /// play step says so, and whether it's still where it was chosen.
    private func quit(_ app: CheckableApp) {
        appQuit = true
        appNotFound = !reader.appExists(at: app.url)
        stage = .playTimedOut
    }

    /// The window closed: a check under way stops, the warning closes, and
    /// nothing more starts. A finished check stays kept.
    func windowClosed() {
        windowIsOpen = false
        presenter?.closeChooser()
        presenter?.closeWarning()
        stopWork()
        stopRun()
    }

    func stopWork() {
        work?.cancel()
        work = nil
    }
}
