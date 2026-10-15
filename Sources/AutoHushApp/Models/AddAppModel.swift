import Foundation
import CheckedPlayers

/// How adding an app goes (Add an App…), step by step, for its window
/// (W2): choose the app, allow what the check needs (only what that app
/// needs, all at once), reopen it with its launch option if it needs one,
/// play something in it, the check (after a warning, W6), then what worked
/// and Use.
@MainActor
@Observable
final class AddAppModel {
    enum Stage: Equatable {
        case choosing
        /// The chosen app opening in the background, or being looked at.
        case opening
        case allowing
        /// Asks before reopening it with its launch option.
        case reopenAsked
        case reopening
        case waitingToPlay(since: Date)
        case playTimedOut
        /// It plays: the check can start (its Continue… shows the warning).
        case ready
        case checking
        case stopped
        case failed
        case done(CheckResult)
    }

    enum Step: CaseIterable {
        case choose, allow, reopen, play, check, use
    }

    enum Mark: Equatable {
        case todo, current, busy, done, failed
    }

    enum ReopenOutcome: Equatable {
        case reopened, skipped
    }

    /// How long the user has to start the app playing.
    static let playWait: TimeInterval = 120

    private(set) var stage = Stage.choosing
    private(set) var apps: [CheckableApp] = []
    private(set) var isLoadingApps = false
    var search = ""
    var selectedID: String?
    private(set) var chosen: CheckableApp?
    private(set) var traits: CheckedAppTraits?
    private(set) var permissions = CheckPermissions()
    /// It ran without the launch option it needs: the Reopen step shows.
    private(set) var needsReopen = false
    private(set) var reopenOutcome: ReopenOutcome?
    /// The last reopen or open didn't go.
    private(set) var reopenFailed = false
    private(set) var openFailed = false
    /// Why the app last picked on the disk can't be checked.
    var otherAppProblem: OtherAppProblem?
    /// The check found Accessibility missing after all (exit status 3).
    private(set) var permissionMissingInCheck = false
    private(set) var progress = CheckProgress()
    /// The chosen app quit while it was waited for, or during the check.
    private(set) var appQuit = false
    /// Why the last check couldn't finish, as far as AutoHush can tell.
    private(set) var failureReason: PlayerCheckEnd.Reason?
    /// Audio Recording was allowed in System Settings: macOS applies it once
    /// AutoHush reopens.
    private(set) var audioAwaitsReopen = false
    /// A check that was stopped and still puts things back: the next one
    /// waits for it.
    private(set) var isEndingLastCheck = false

    @ObservationIgnored var services: AddAppServices
    @ObservationIgnored private var run: (any CheckRunning)?
    /// A stopped check still putting things back.
    @ObservationIgnored private var endingRun: (any CheckRunning)?
    /// Watching the permissions, or waiting for the app to play.
    @ObservationIgnored private var work: Task<Void, Never>?
    /// The window is open: closed, nothing more starts (a warning's Start
    /// after the window closed, say).
    @ObservationIgnored private var windowIsOpen = false

    init(services: AddAppServices) {
        self.services = services
    }

    // MARK: - What the window shows

    /// The steps shown: Reopen only for an app that needs it.
    var steps: [Step] { Step.allCases.filter { $0 != .reopen || needsReopen } }

    /// Its number among the steps shown.
    func number(of step: Step) -> Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    func mark(of step: Step) -> Mark {
        let order = Step.allCases
        let at = order.firstIndex(of: currentStep)!
        let index = order.firstIndex(of: step)!
        if index < at { return .done }
        if index > at { return .todo }
        switch stage {
        case .opening, .reopening, .checking: return .busy
        case .playTimedOut, .stopped, .failed: return .failed
        case .done(let result): return result.setup == nil ? .failed : .current
        default: return .current
        }
    }

    /// The step the stage is in.
    var currentStep: Step {
        switch stage {
        case .choosing, .opening: .choose
        case .allowing: .allow
        case .reopenAsked, .reopening: .reopen
        case .waitingToPlay, .playTimedOut: .play
        case .ready, .checking, .stopped, .failed: .check
        case .done: .use
        }
    }

    /// The apps matching the search: those in Now Playing first.
    var shownApps: (inNowPlaying: [CheckableApp], others: [CheckableApp]) {
        let search = search.trimmingCharacters(in: .whitespaces)
        let matching = search.isEmpty ? apps : apps.filter { $0.name.localizedStandardContains(search) }
        return (matching.filter { $0.nowPlaying != nil }, matching.filter { $0.nowPlaying == nil })
    }

    /// The apps shown, in the list's order.
    var shownAppsInOrder: [CheckableApp] { shownApps.inNowPlaying + shownApps.others }

    var canContinueWithApp: Bool { stage == .choosing && apps.contains { $0.id == selectedID } }

    /// Another app can be chosen instead: one is, and nothing is under way.
    var canChangeApp: Bool {
        switch stage {
        case .choosing, .opening, .reopening, .checking: false
        default: true
        }
    }

    var result: CheckResult? {
        if case .done(let result) = stage { result } else { nil }
    }

    /// AntiDot mode is on: nothing listens to the app, and it can't be muted.
    var antiDot: Bool { services.antiDot() }

    // MARK: - Steps

    /// Ready for an app, from the first step; the apps read again. A check
    /// that finished and wasn't used yet comes back where it ended.
    func reset() {
        windowIsOpen = true
        resetSteps()
        search = ""
        if let kept = services.keptChecks.load(now: services.now()), services.exists(kept.app.url) {
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
        otherAppProblem = nil
        appQuit = false
        failureReason = nil
        progress = CheckProgress()
    }

    /// The check's result as it was kept: its app chosen, the last step.
    private func restore(_ kept: KeptCheck) {
        chosen = kept.app
        selectedID = kept.app.id
        let traits = services.traits(kept.app.url)
        self.traits = traits
        stage = .done(kept.result)
        Task { [weak self] in
            guard let self else { return }
            self.permissions = await self.services.permissions(kept.app, traits.scriptable)
        }
    }

    /// Stops a check under way: it puts things back before it ends, and the
    /// next one waits for that (`isEndingLastCheck`).
    private func stopRun() {
        guard let run else { return }
        run.stop()
        self.run = nil
        endingRun = run
        isEndingLastCheck = true
    }

    /// The first step's button: the window that lists the apps.
    func openChooser() {
        guard stage == .choosing else { return }
        search = ""
        services.showChooser()
    }

    /// Chooses `app` (from the list, or picked on the disk) and goes on.
    func choose(_ app: CheckableApp) {
        guard stage == .choosing else { return }
        if !apps.contains(where: { $0.id == app.id }) { apps.append(app) }
        selectedID = app.id
        otherAppProblem = nil
        services.closeChooser()
        continueWithApp()
    }

    /// Other App…'s pick: chosen, or why it can't be.
    func chooseOther(at url: URL) {
        switch services.appAt(url) {
        case .success(let app): choose(app)
        case .failure(let problem): otherAppProblem = problem
        }
    }

    /// The first step's Change…: from the first step again, its list open.
    /// A kept result is forgotten.
    func changeApp() {
        guard canChangeApp else { return }
        services.keptChecks.forget()
        resetSteps()
        search = ""
        services.showChooser()
    }

    func loadApps() async {
        isLoadingApps = true
        apps = await services.listApps()
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
        let traits = services.traits(app.url)
        self.traits = traits
        openFailed = false
        appQuit = false
        stage = .opening
        work = Task { [weak self] in
            guard let self else { return }
            if !self.services.isRunning(app.bundleID) {
                guard await self.services.open(app, traits.needsLaunchOption), !Task.isCancelled else {
                    if !Task.isCancelled {
                        self.openFailed = true
                        self.stage = .choosing
                    }
                    return
                }
            } else if traits.needsLaunchOption {
                self.needsReopen = await self.services.runsWithLaunchOption(app) == false
            }
            guard !Task.isCancelled else { return }
            self.stage = .allowing
            self.watchPermissions()
        }
    }

    /// Reads the permissions about once a second while they're asked for,
    /// and goes on once they're all allowed (or with `continueWithoutAll`).
    private func watchPermissions() {
        guard let app = chosen, let traits else { return }
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .allowing {
                self.permissions = await self.services.permissions(app, traits.scriptable)
                if self.permissions.allAllowed(antiDot: self.antiDot) {
                    self.permissionMissingInCheck = false
                    self.afterPermissions()
                    return
                }
                await self.services.sleep(.seconds(1))
            }
        }
    }

    /// The Allow step's Continue, once what's needed is allowed: the check
    /// goes on without the rest, checking less.
    func continueWithoutAll() {
        guard stage == .allowing, permissions.neededAllowed else { return }
        stopWork()
        afterPermissions()
    }

    /// A permission's Allow…. Audio Recording turned on in System Settings
    /// applies once AutoHush reopens: the window then offers to.
    func request(_ permission: CheckPermission) {
        guard let app = chosen else { return }
        let current = permissions
        if permission == .audioRecording, current.audio == .denied { audioAwaitsReopen = true }
        Task { await services.request(permission, app, current) }
    }

    /// Reopen AutoHush, for Audio Recording: a finished check is kept.
    func reopenAutoHush() {
        services.reopenAutoHush()
    }

    private func afterPermissions() {
        if needsReopen, reopenOutcome == nil {
            stage = .reopenAsked
        } else {
            waitForPlaying()
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
            let reopened = await self.services.reopen(app)
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
        let since = services.now()
        appQuit = false
        failureReason = nil
        stage = .waitingToPlay(since: since)
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .waitingToPlay(since: since) {
                if !self.services.isRunning(app.bundleID) {
                    self.appQuit = true
                    self.stage = .playTimedOut
                    return
                }
                if await self.services.isPlaying(app, traits), self.stage == .waitingToPlay(since: since) {
                    self.stage = .ready
                    return
                }
                if self.services.now().timeIntervalSince(since) >= Self.playWait {
                    self.stage = .playTimedOut
                    return
                }
                await self.services.sleep(.milliseconds(500))
            }
        }
    }

    /// Opens the app again after it quit, then waits for it to play.
    func openAppAgain() {
        guard let app = chosen, let traits else { return }
        appQuit = false
        stage = .opening
        work = Task { [weak self] in
            guard let self else { return }
            let opened = await self.services.open(app, traits.needsLaunchOption)
            guard !Task.isCancelled else { return }
            if opened {
                self.waitForPlaying()
            } else {
                self.appQuit = true
                self.stage = .playTimedOut
            }
        }
    }

    /// The check step's Continue…: the warning before the check.
    func continueToCheck() {
        guard stage == .ready else { return }
        services.showWarning()
    }

    /// The warning's Start: the check runs, with its panel, once a stopped
    /// one has put things back; once it ends, what it found (or why it didn't).
    func startCheck() {
        guard stage == .ready, windowIsOpen, let app = chosen else { return }
        progress = CheckProgress()
        failureReason = nil
        stage = .checking
        Task { [weak self] in
            if let ending = self?.endingRun { _ = await ending.waitForEnd() }
            guard let self, self.stage == .checking, self.windowIsOpen, self.run == nil else { return }
            guard let run = self.services.startCheck(app, !self.antiDot, { [weak self] line in self?.progress.add(line) }) else {
                self.stage = .failed
                self.failureReason = .other
                return
            }
            self.run = run
            self.services.checkStarted(app)
            let end = await run.waitForEnd()
            self.ended(run, end, app: app)
        }
    }

    /// A check ended: the panel goes; for the check under way, what it found.
    private func ended(_ ending: any CheckRunning, _ end: PlayerCheckEnd, app: CheckableApp) {
        if endingRun === ending {
            endingRun = nil
            isEndingLastCheck = false
            if run == nil { services.checkEnded() }
            return
        }
        guard run === ending else { return } // started again since
        services.checkEnded()
        run = nil
        switch end {
        case .finished(let result?):
            if result.setup == nil, !services.isRunning(app.bundleID) {
                // It quit during the check: nothing could be tried.
                failureReason = .appQuit
                stage = .failed
                return
            }
            stage = .done(result)
            services.keptChecks.save(KeptCheck(app: app, result: result, at: services.now()))
            // What muting needs, as it stands now (the last step may offer it).
            if result.setup == nil, let traits {
                Task { [weak self] in
                    guard let self else { return }
                    self.permissions = await self.services.permissions(app, traits.scriptable)
                }
            }
        case .finished(nil), .failed:
            failureReason = !services.exists(app.url) ? .appNotFound : !services.isRunning(app.bundleID) ? .appQuit : .other
            stage = .failed
        case .stopped:
            stage = .stopped
        case .permissionMissing:
            permissionMissingInCheck = true
            stage = .allowing
            watchPermissions()
        }
    }

    /// Stop (the window's, the panel's): the check puts everything back first.
    func stopCheck() {
        run?.stop()
    }

    /// After a check that stopped, failed or found no way: from playing again.
    func checkAgain() {
        switch stage {
        case .stopped, .failed, .playTimedOut: waitForPlaying()
        case .done(let result) where result.setup == nil: waitForPlaying()
        default: break
        }
    }

    /// Shows the newest check's log (after one couldn't finish).
    func showLog() {
        services.showLog()
    }

    /// Muting needs Audio Recording, and isn't available in AntiDot mode
    /// (the last step's Mute It Instead).
    var canMute: Bool { permissions.audio == .allowed && !antiDot }

    /// The last step's Mute It Instead, when no way worked: the app is
    /// muted while other apps play, never paused, and made the player.
    func useMuting() {
        guard let result, result.setup == nil, canMute, let app = chosen else { return }
        let setup = PlayerSetup(bundleID: app.bundleID, name: app.name, appURL: app.url, ways: [.mute])
        services.keptChecks.forget()
        services.use(CheckResult(ways: result.ways, setup: setup), reopenOutcome != .skipped)
        services.close()
    }

    /// Asks for Audio Recording from the last step, for muting, and follows it.
    func allowMuting() {
        guard let app = chosen, let traits else { return }
        let current = permissions
        if current.audio == .denied { audioAwaitsReopen = true }
        Task { [weak self] in
            await self?.services.request(.audioRecording, app, current)
            for _ in 0..<60 {
                guard let self, self.result != nil, !self.canMute else { return }
                self.permissions = await self.services.permissions(app, traits.scriptable)
                await self.services.sleep(.seconds(1))
            }
        }
    }

    /// The last step's Use: keeps what worked and makes the app the player
    /// (asking to reopen it unless the user skipped that here).
    func use() {
        guard let result, result.setup != nil else { return }
        services.keptChecks.forget()
        services.use(result, reopenOutcome != .skipped)
        services.close()
    }

    /// The window closed: a check under way stops, the warning closes, and
    /// nothing more starts. A finished check stays kept.
    func windowClosed() {
        windowIsOpen = false
        services.closeChooser()
        services.closeWarning()
        stopWork()
        stopRun()
    }

    private func stopWork() {
        work?.cancel()
        work = nil
    }
}
