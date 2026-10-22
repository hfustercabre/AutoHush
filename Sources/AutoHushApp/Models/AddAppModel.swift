import Foundation
import CheckedPlayers
import PlayerCheckKit

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

    enum ReopenOutcome: String, Codable, Equatable {
        case reopened, skipped
    }

    /// How long the user has to start the app playing.
    static let playWait: TimeInterval = 120

    private(set) var stage = Stage.choosing
    private(set) var apps: [CheckableApp] = []
    private(set) var isLoadingApps = false
    var search = ""
    /// Another selection drops Other App…'s warning, which was about the
    /// app picked on the disk (A1, the user, 2026-10-19).
    var selectedID: String? {
        didSet { if selectedID != oldValue { otherAppProblem = nil } }
    }
    private(set) var chosen: CheckableApp?
    private(set) var traits: CheckedAppTraits?
    private(set) var permissions = CheckPermissions() {
        didSet { readMacMuting() } // as the steps that say how the check mutes show
    }
    /// It ran without the launch option it needs: the Reopen step shows.
    private(set) var needsReopen = false
    private(set) var reopenOutcome: ReopenOutcome?
    /// The last reopen or open didn't go.
    private(set) var reopenFailed = false
    private(set) var openFailed = false
    /// Why the app last picked on the disk can't be checked.
    var otherAppProblem: OtherAppProblem?
    /// The check found Accessibility missing after all (`CheckExitStatus.permissionMissing`).
    private(set) var permissionMissingInCheck = false
    private(set) var progress = CheckProgress()
    /// The chosen app quit while it was waited for, or during the check.
    private(set) var appQuit = false
    /// Why the last check couldn't finish, as far as AutoHush can tell.
    private(set) var failureReason: PlayerCheckEnd.Reason?
    /// Audio Recording was allowed in System Settings (here or elsewhere in
    /// AutoHush): macOS applies it once AutoHush reopens.
    var audioAwaitsReopen: Bool { permissions.audio == .needsReopen }
    /// A check that was stopped and still puts things back: the next one
    /// waits for it.
    private(set) var isEndingLastCheck = false

    /// The apps on the Mac, and the check's helper (`nil`: missing from
    /// the app, so nothing can be checked).
    @ObservationIgnored private let reader: any AppReading
    @ObservationIgnored private let helper: any CheckHelping?
    /// What it needs from the rest of AutoHush, and what it shows through
    /// the feature that owns it (weak: they own it).
    @ObservationIgnored private weak var host: any AddAppHost?
    @ObservationIgnored private weak var presenter: any AddAppPresenting?
    /// Where a finished check's result is kept until it's used or replaced
    /// (a reopen of AutoHush, or the window closed, doesn't lose it).
    @ObservationIgnored private let keptChecks: KeptCheckStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (Duration) async -> Void
    @ObservationIgnored private var run: any CheckRunning?
    /// A stopped check still putting things back.
    @ObservationIgnored private var endingRun: any CheckRunning?
    /// Watching the permissions, or waiting for the app to play.
    @ObservationIgnored private var work: Task<Void, Never>?
    /// The window is open: closed, nothing more starts (a warning's Start
    /// after the window closed, say).
    @ObservationIgnored private var windowIsOpen = false

    init(reader: any AppReading, helper: any CheckHelping?, host: any AddAppHost?, presenter: any AddAppPresenting,
         keptChecks: KeptCheckStore = KeptCheckStore(), now: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.reader = reader
        self.helper = helper
        self.host = host
        self.presenter = presenter
        self.keptChecks = keptChecks
        self.now = now
        self.sleep = sleep
    }

    /// The check's helper is in the app: without it, nothing can be checked.
    var hasHelper: Bool { helper != nil }

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
        case .done: return choosableWays.isEmpty ? .failed : .current
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

    /// The ways that worked, in every window state or in some, that AutoHush
    /// can run, the recommended first (the setup's order): the user chooses
    /// one (U2, the user's pick, 2026-10-15). None: nothing it can use worked.
    var choosableWays: [CheckResult.WayKind] {
        guard let result, let setup = result.setup else { return [] }
        let worked = Set(result.ways.filter(\.worked).map(\.kind))
        return setup.ways.compactMap(\.kind).filter { worked.contains($0) && !($0 == .panel && panelNeedsSound && antiDot) }
    }

    /// The Now Playing panel worked, but its row doesn't follow the app: only
    /// its sound tells, which AntiDot mode doesn't hear, so it can't be chosen
    /// then, as muting can't (the user, 2026-10-16).
    var panelNeedsSound: Bool { result?.setup?.panelRowIsStale == true }

    /// Check Again is offered in the last step: with nothing to use (beside
    /// Mute It Instead), and beside Use when Now Playing was hidden in the
    /// menu bar, so its panel wasn't tried (the user, 2026-10-16).
    var offersCheckAgain: Bool {
        guard let result else { return false }
        return choosableWays.isEmpty || result.ways.contains { $0.mark == .menuBarHidden }
    }

    /// The way Use makes AutoHush use: the user's choice, else the recommended.
    var chosenWay: CheckResult.WayKind? {
        pickedWay.flatMap { choosableWays.contains($0) ? $0 : nil } ?? choosableWays.first
    }

    private(set) var pickedWay: CheckResult.WayKind?

    func choose(_ way: CheckResult.WayKind) {
        guard choosableWays.contains(way) else { return }
        pickedWay = way
    }

    /// AntiDot mode is on: nothing listens to the app, and it can't be muted.
    var antiDot: Bool {
        _ = antiDotChanges // read, so the window follows `turnOffAntiDot`
        return host?.isAntiDot ?? true
    }

    /// How many times AntiDot mode was turned off from here.
    private var antiDotChanges = 0

    /// What the check mutes while it plays and pauses the app.
    enum CheckMuting {
        /// The app itself, by tapping its sound: Audio Recording allowed,
        /// AntiDot mode off.
        case app
        /// The Mac's output, since the app alone can't be (the user, 2026-10-18).
        case mac
        /// Nothing: the output has no mute control, so the app is heard.
        case none
    }

    var checkMuting: CheckMuting {
        if permissions.audio == .allowed && !antiDot { return .app }
        return macCanMute ? .mac : .none
    }

    /// Whether the Mac's output could be muted, as last read: as the
    /// permissions are read, and as the warning before the check opens. The
    /// steps' notes, the warning and the check's start all go by it, so
    /// they agree, and Core Audio isn't asked at every drawing. The check's
    /// start mutes the output in use then (`OutputMute.mute`).
    private(set) var macCanMute = false

    private func readMacMuting() {
        let canMute = presenter?.canMuteOutput ?? false
        if canMute != macCanMute { macCanMute = canMute }
    }

    /// Now Playing was hidden in the menu bar, so its panel wasn't tried:
    /// the last step offers to open where it's shown, then Check Again.
    var nowPlayingHidden: Bool { result?.ways.contains { $0.mark == .menuBarHidden } == true }

    func openMenuBarSettings() {
        presenter?.openMenuBarSettings()
    }

    /// The last step's Turn Off AntiDot Mode, when nothing that worked can be
    /// used in it: a way only the app's sound tells, or muting, then can.
    func turnOffAntiDot() {
        host?.turnOffAntiDot()
        antiDotChanges += 1
    }

    // MARK: - Steps

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
        otherAppProblem = nil
        appQuit = false
        failureReason = nil
        progress = CheckProgress()
    }

    /// The check's result as it was kept: its app chosen, the last step.
    private func restore(_ kept: KeptCheck) {
        chosen = kept.app
        selectedID = kept.app.id
        let traits = reader.traits(ofAppAt: kept.app.url)
        self.traits = traits
        needsReopen = kept.needsReopen
        reopenOutcome = kept.reopenOutcome
        stage = .done(kept.result)
        Task { [weak self] in
            guard let self else { return }
            self.permissions = await self.readPermissions(kept.app, scriptable: traits.scriptable)
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

    /// Change… forgets a check that has run (about 3 minutes), so it asks first.
    var changeAppForgetsCheck: Bool { result != nil }

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

    /// Reads the permissions about once a second while they're asked for,
    /// and goes on once they're all allowed (or with `continueWithoutAll`).
    private func watchPermissions() {
        guard let app = chosen, let traits else { return }
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .allowing {
                self.permissions = await self.readPermissions(app, scriptable: traits.scriptable)
                if self.permissions.allAllowed(antiDot: self.antiDot) {
                    self.permissionMissingInCheck = false
                    self.afterPermissions()
                    return
                }
                await self.sleep(.seconds(1))
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

    /// A permission's Allow…, then the permissions read again, so its row
    /// follows at once. Audio Recording turned on in System Settings applies
    /// once AutoHush reopens: the window then offers to.
    func request(_ permission: CheckPermission) {
        guard let app = chosen, let traits else { return }
        let current = permissions
        Task { [weak self] in
            guard let self else { return }
            await self.host?.requestCheckPermission(permission, app: app, current: current)
            guard self.chosen == app else { return }
            self.permissions = await self.readPermissions(app, scriptable: traits.scriptable)
        }
    }

    /// Reopen AutoHush, for Audio Recording: a finished check is kept.
    func reopenAutoHush() {
        host?.reopenForAudioRecording()
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
        failureReason = nil
        stage = .waitingToPlay(since: since)
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .waitingToPlay(since: since) {
                if !self.reader.isRunning(app.bundleID) {
                    self.appQuit = true
                    self.stage = .playTimedOut
                    return
                }
                if await self.reader.isPlaying(app, traits: traits), self.stage == .waitingToPlay(since: since) {
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
        guard let app = chosen, let traits else { return }
        appQuit = false
        stage = .opening
        work = Task { [weak self] in
            guard let self else { return }
            let opened = await self.reader.open(app, withLaunchOption: traits.needsLaunchOption)
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
        readMacMuting() // what the warning says, and the check does
        presenter?.showWarning()
    }

    /// The warning's Start: the check runs, with its panel, once a stopped
    /// one has put things back; once it ends, what it found (or why it didn't).
    func startCheck() {
        guard stage == .ready, windowIsOpen, let app = chosen else { return }
        progress = CheckProgress()
        failureReason = nil
        pickedWay = nil
        stage = .checking
        Task { [weak self] in
            if let ending = self?.endingRun { _ = await ending.waitForEnd() }
            guard let self, self.stage == .checking, self.windowIsOpen, self.run == nil else { return }
            guard let run = self.helper?.startCheck(app, taps: !self.antiDot, onLine: { [weak self] line in self?.progress.add(line) }) else {
                self.stage = .failed
                self.failureReason = .other
                return
            }
            self.run = run
            self.presenter?.checkStarted(app)
            let end = await run.waitForEnd()
            self.ended(run, end, app: app)
        }
    }

    /// A check ended: the panel goes; for the check under way, what it found.
    private func ended(_ ending: any CheckRunning, _ end: PlayerCheckEnd, app: CheckableApp) {
        if endingRun === ending {
            endingRun = nil
            isEndingLastCheck = false
            if run == nil { presenter?.checkEnded() }
            return
        }
        guard run === ending else { return } // started again since
        presenter?.checkEnded()
        run = nil
        switch end {
        case .finished(let result?):
            if result.setup == nil, !reader.isRunning(app.bundleID) {
                // It quit during the check: nothing could be tried.
                failureReason = .appQuit
                stage = .failed
                return
            }
            stage = .done(result)
            keptChecks.save(KeptCheck(app: app, result: result, at: now(),
                                               needsReopen: needsReopen, reopenOutcome: reopenOutcome))
            // What muting needs, as it stands now (the last step may offer it).
            if choosableWays.isEmpty, let traits {
                Task { [weak self] in
                    guard let self else { return }
                    self.permissions = await self.readPermissions(app, scriptable: traits.scriptable)
                }
            }
        case .finished(nil), .failed, .stopped:
            // A check again of an app whose result is kept (Check Again
            // beside Use) that doesn't finish: that result comes back, Use
            // with it (the workflow audit, 2026-10-22).
            if let kept = keptChecks.load(now: now()), kept.app.bundleID == app.bundleID {
                restore(kept)
            } else if case .stopped = end {
                stage = .stopped
            } else {
                failureReason = !reader.appExists(at: app.url) ? .appNotFound : !reader.isRunning(app.bundleID) ? .appQuit : .other
                stage = .failed
            }
        case .permissionMissing:
            permissionMissingInCheck = true
            stage = .allowing
            watchPermissions()
        }
    }

    /// Stop (the window's, the panel's): the check puts everything back
    /// first. While the last one still does, the new one never starts: back
    /// to its step (the workflow audit, 2026-10-22).
    func stopCheck() {
        guard let run else {
            if stage == .checking { stage = .ready }
            return
        }
        run.stop()
    }

    /// After a check that stopped or failed, or one whose last step offers
    /// it (`offersCheckAgain`): from playing again.
    func checkAgain() {
        switch stage {
        case .stopped, .failed, .playTimedOut: waitForPlaying()
        case .done where offersCheckAgain: waitForPlaying()
        default: break
        }
    }

    /// There's a check's log to show.
    var canShowLog: Bool { presenter?.hasCheckLog ?? false }

    /// Shows the newest check's log (after one couldn't finish).
    func showLog() {
        presenter?.showCheckLog()
    }

    /// Muting needs Audio Recording, and isn't available in AntiDot mode
    /// (the last step's Mute It Instead).
    var canMute: Bool { permissions.audio == .allowed && !antiDot }

    /// The last step's Mute It Instead, when no way it can use worked: the
    /// app is muted while other apps play, never paused, and made the player.
    func useMuting() {
        guard let result, choosableWays.isEmpty, canMute, let app = chosen else { return }
        let setup = PlayerSetup(bundleID: app.bundleID, name: app.name, appURL: app.url, ways: [.mute])
        keptChecks.forget()
        host?.useCheckedApp(CheckResult(ways: result.ways, setup: setup), asksToReopen: reopenOutcome != .skipped)
        presenter?.closeWindow()
    }

    /// Asks for Audio Recording from the last step, for muting, and follows it.
    func allowMuting() {
        guard let app = chosen, let traits else { return }
        let current = permissions
        Task { [weak self] in
            await self?.host?.requestCheckPermission(.audioRecording, app: app, current: current)
            for _ in 0..<60 {
                guard let self, self.result != nil, !self.canMute else { return }
                self.permissions = await self.readPermissions(app, scriptable: traits.scriptable)
                await self.sleep(.seconds(1))
            }
        }
    }

    /// The last step's Use: keeps what worked and makes the app the player
    /// (asking to reopen it unless the user skipped that here).
    func use() {
        guard let result, var setup = result.setup, let way = chosenWay else { return }
        // Only the chosen way: the others as its backup are parked (the user, 2026-10-15).
        setup.ways = setup.ways.filter { $0.kind == way }
        keptChecks.forget()
        // The page's learned Play/Pause goes with the page: without it, the
        // app would wait to learn it and never pause (2026-10-18).
        host?.useCheckedApp(CheckResult(ways: result.ways, setup: setup, pageButton: way == .page ? result.pageButton : nil),
                            asksToReopen: reopenOutcome != .skipped)
        presenter?.closeWindow()
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

    private func stopWork() {
        work?.cancel()
        work = nil
    }

    /// What the check of `app` needs, as it stands now.
    private func readPermissions(_ app: CheckableApp, scriptable: Bool) async -> CheckPermissions {
        await host?.checkPermissions(app, scriptable: scriptable) ?? CheckPermissions()
    }
}
