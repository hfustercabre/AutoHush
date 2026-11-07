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
        checkAgainState = nil
    }

    /// The check's result as it was kept: its app chosen, the last step.
    func restore(_ kept: KeptCheck) {
        chosen = kept.app
        selectedID = kept.app.id
        let traits = reader.traits(ofAppAt: kept.app.url)
        self.traits = traits
        needsReopen = kept.needsReopen
        reopenOutcome = kept.reopenOutcome
        checkAgainState = nil
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

    /// Fine-Tuning's Check Again… for the app at `url` (W-3, the user,
    /// 2026-11-07): on another app (its list, its steps, or its result not
    /// yet used), it starts over on this one, as from its first step; as it
    /// is while it shows this one, or while a check is under way, which
    /// can't be stopped from there. Another app's result stays kept, as a
    /// closed window keeps it: only Change… forgets it, after asking. An
    /// app it can't read (moved or deleted since) starts over too, at the
    /// first step, its list open with why, as Other App… says it (F-7, the
    /// code check of 2026-11-07).
    func startOver(onAppAt url: URL) {
        switch stage {
        case .choosing:
            chooseOther(at: url)
        case .checking:
            return
        default:
            let read = reader.app(at: url)
            if case .success(let app) = read, app.bundleID == chosen?.bundleID { return }
            presenter?.closeWarning() // its Start was for the app before
            resetSteps()
            switch read {
            case .success(let app): choose(app)
            case .failure(let problem):
                search = ""
                presenter?.showChooser()
                otherAppProblem = problem // once its list is open, so VoiceOver hears it too
            }
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
        checkAgainState?.windowMissing = false
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
                self.checkAgainState?.windowMissing = !windowOpen
                if windowOpen, await self.reader.isPlaying(app, traits: traits), self.stage == .waitingToPlay(since: since) {
                    // Whether the check will find its windows closed, for the warning.
                    let closed = self.waitsForWindow ? false : !(await self.reader.hasWindowWithinReach(app))
                    guard self.stage == .waitingToPlay(since: since) else { return }
                    self.appWindowsClosed = closed
                    self.stage = .ready
                    await self.watchUntilStart(app)
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

    /// Back at the check step with no wait running (Stop while the last
    /// check still put things back): watched until the check starts, as
    /// after the wait (WA2, the review of 2026-10-31).
    func watchAfterStopUntilStart() {
        guard let app = chosen, stage == .ready else { return }
        stopWork() // a watch still asleep would go on beside this one (the 1.2.9 review)
        work = Task { [weak self] in await self?.watchUntilStart(app) }
    }

    /// Ready: the app is watched until the check starts, so a change that
    /// undoes the play step is told at once, not by Start the Check (L7,
    /// 2026-10-31), the warning closed: it quit, its quit step as while it
    /// was waited for, also after Check Again (WA1, the user, 2026-10-31);
    /// after Check Again with its windows closed, its window closed again,
    /// the wait for one (WA7, the user, 2026-10-31); otherwise, whether
    /// its windows are closed, for the warning (`appWindowsClosed`, W2 of
    /// 1.2.2, 2026-11-07). Its windows only every 2 s: a look at one off
    /// screen reads the app by Accessibility and searches the other
    /// desktops (up to 1 s), for as long as the user stays on this step
    /// (the code check of 2026-11-02).
    private func watchUntilStart(_ app: CheckableApp) async {
        var round = 0
        while !Task.isCancelled, stage == .ready {
            await sleep(.milliseconds(500))
            guard !Task.isCancelled, stage == .ready else { return }
            if !reader.isRunning(app.bundleID) {
                presenter?.closeWarning()
                quit(app)
                return
            }
            round += 1
            // Its windows looked at every 2 s: a look reads the other desktops too.
            guard round.isMultiple(of: 4) else { continue }
            let windowOpen = await reader.hasWindowWithinReach(app)
            guard !Task.isCancelled, stage == .ready else { return }
            guard windowsLookedAt(open: windowOpen) else { return }
        }
    }

    /// The chosen app's windows looked at now, not at the watch's next look
    /// (every 2 s): as the warning before the check comes up, comes back in
    /// front, and at its Start, so it says what the check will do (F-6, the
    /// code check of 2026-11-07).
    func lookAtWindows() async {
        guard stage == .ready, let app = chosen else { return }
        let windowOpen = await reader.hasWindowWithinReach(app)
        guard stage == .ready, chosen?.bundleID == app.bundleID else { return }
        windowsLookedAt(open: windowOpen)
    }

    /// What a look at the app's windows found, while it's ready: after
    /// Check Again with its windows closed, its window closed again, the
    /// wait for one (`false`: no longer ready); otherwise whether they're
    /// all closed, for the warning.
    @discardableResult
    private func windowsLookedAt(open windowOpen: Bool) -> Bool {
        if waitsForWindow, !windowOpen {
            presenter?.closeWarning()
            stopWork() // a watch still asleep would go on beside the wait
            waitForPlaying()
            return false
        }
        appWindowsClosed = !windowOpen
        return true
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
