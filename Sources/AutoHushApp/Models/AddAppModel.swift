import AppKit
import Foundation
import AutoHushKit
import CheckedPlayers

/// An app Add an App… offers to check: one that can play, and that
/// AutoHush doesn't support already.
struct CheckableApp: Identifiable, Equatable, Sendable {
    let bundleID: String
    let name: String
    let url: URL
    /// In macOS's Now Playing list: whether it plays there; `nil` when it
    /// isn't listed (or the list can't be read).
    var nowPlaying: Bool?
    /// The browser that made it, when it's a Chromium browser's web app
    /// ("Google Chrome", "Brave Browser"): two of one site look alike.
    var browserName: String?

    var id: String { bundleID }

    init(bundleID: String, name: String, url: URL, nowPlaying: Bool? = nil, browserName: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.nowPlaying = nowPlaying
        self.browserName = browserName
    }

    /// The name of the browser that made the app at `url`, if it's a
    /// Chromium browser's web app.
    static func browserName(ofAppAt url: URL) -> String? {
        guard let browser = CheckedAppTraits.browser(ofAppAt: url),
              let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else { return nil }
        return FileManager.default.displayName(atPath: browserURL.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// What a check needs allowed for the chosen app.
struct CheckPermissions: Equatable {
    var accessibility = false
    var audio = PermissionAccess.notAsked
    /// Automation for the app; `nil` when it can't be scripted.
    var automation: PermissionAccess?

    var allAllowed: Bool { accessibility && audio == .allowed && (automation == nil || automation == .allowed) }

    /// What the check can't go without: Accessibility (the app's menus, its
    /// page, the Now Playing panel, its window moved, the mouse and keyboard
    /// blocked). Without the others it checks less (`missingOptional`).
    var neededAllowed: Bool { accessibility }

    /// The ones not allowed that the check can go without.
    var missingOptional: [CheckPermission] {
        (audio == .allowed ? [] : [.audioRecording]) + (automation == nil || automation == .allowed ? [] : [.automation])
    }
}

/// Why an app picked from the disk (Other App…) can't be checked.
enum OtherAppProblem: Error, Equatable {
    /// Not an app bundle with a bundle ID.
    case notAnApp
    /// AutoHush supports it already: it's chosen from the players.
    case supported(String)
    /// AutoHush itself.
    case autoHush
}

/// One of `CheckPermissions`, for its Allow button.
enum CheckPermission: Equatable {
    case accessibility, audioRecording, automation
}

/// A check running, for the model: Stop, and how it ended.
@MainActor
protocol CheckRunning: AnyObject {
    func stop()
    func waitForEnd() async -> PlayerCheckEnd
}

extension PlayerCheckRun: CheckRunning {}

/// What adding an app does outside the model: the app's are live, tests'
/// stand in for them.
@MainActor
struct AddAppServices {
    var listApps: @MainActor () async -> [CheckableApp]
    /// The app at a place picked on the disk (Other App…), or why it can't be checked.
    var appAt: @MainActor (URL) -> Result<CheckableApp, OtherAppProblem> = { _ in .failure(.notAnApp) }
    /// The window that lists the apps to choose (the first step's).
    var showChooser: @MainActor () -> Void = {}
    var closeChooser: @MainActor () -> Void = {}
    var traits: @MainActor (URL) -> CheckedAppTraits
    var isRunning: @MainActor (String) -> Bool
    /// Opens it in the background (with its launch option when it needs
    /// one); whether it did.
    var open: @MainActor (CheckableApp, _ withLaunchOption: Bool) async -> Bool
    /// Whether it runs with the launch option it needs; `nil` when it needs
    /// none or isn't running.
    var runsWithLaunchOption: @MainActor (CheckableApp) async -> Bool?
    /// Quits it and opens it again with its launch option; whether it did.
    var reopen: @MainActor (CheckableApp) async -> Bool
    var permissions: @MainActor (CheckableApp, _ scriptable: Bool) async -> CheckPermissions
    var request: @MainActor (CheckPermission, CheckableApp, CheckPermissions) async -> Void
    /// Whether it plays now, as the check judges it (`AppPlaying`).
    var isPlaying: @MainActor (CheckableApp, CheckedAppTraits) async -> Bool
    var startCheck: @MainActor (CheckableApp, _ onLine: @escaping @MainActor @Sendable (String) -> Void) -> (any CheckRunning)?
    /// The warning before the check (W6), whose Start calls `startCheck()`.
    var showWarning: @MainActor () -> Void
    /// The check's panel and shade, while it runs.
    var checkStarted: @MainActor (CheckableApp) -> Void
    var checkEnded: @MainActor () -> Void
    /// Keeps what the check found and makes the app the player.
    var use: @MainActor (CheckResult) -> Void
    var close: @MainActor () -> Void
    var now: @MainActor () -> Date = { Date() }
    var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
}

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
    /// The check found a permission missing after all (exit status 3).
    private(set) var permissionMissingInCheck = false
    private(set) var progress = CheckProgress()

    @ObservationIgnored var services: AddAppServices
    @ObservationIgnored private var run: (any CheckRunning)?
    /// Watching the permissions, or waiting for the app to play.
    @ObservationIgnored private var work: Task<Void, Never>?

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

    var canContinueWithApp: Bool { stage == .choosing && apps.contains { $0.id == selectedID } }

    /// Another app can be chosen instead: one is, and nothing is under way.
    var canChangeApp: Bool {
        switch stage {
        case .choosing, .opening, .reopening, .checking: false
        default: true
        }
    }

    var isChecking: Bool { stage == .checking }

    var result: CheckResult? {
        if case .done(let result) = stage { result } else { nil }
    }

    // MARK: - Steps

    /// Ready for an app, from the first step; the apps read again.
    func reset() {
        resetSteps()
        search = ""
        Task { await loadApps() }
    }

    /// Back to the first step, the apps as they were read.
    private func resetSteps() {
        stopWork()
        run?.stop()
        run = nil
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
        progress = CheckProgress()
    }

    /// The first step's button: the window that lists the apps.
    func openChooser() {
        guard stage == .choosing else { return }
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
    func changeApp() {
        guard canChangeApp else { return }
        resetSteps()
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
                if self.permissions.allAllowed {
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

    func request(_ permission: CheckPermission) {
        guard let app = chosen else { return }
        let current = permissions
        Task { await services.request(permission, app, current) }
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

    /// Waits for the chosen app to play, up to `playWait`.
    func waitForPlaying() {
        guard let app = chosen, let traits else { return }
        let since = services.now()
        stage = .waitingToPlay(since: since)
        work = Task { [weak self] in
            while let self, !Task.isCancelled, self.stage == .waitingToPlay(since: since) {
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

    /// Step 5's Continue…: the warning before the check.
    func continueToCheck() {
        guard stage == .ready else { return }
        services.showWarning()
    }

    /// The warning's Start: the check runs, with its panel; once it ends,
    /// what it found (or why it didn't).
    func startCheck() {
        guard stage == .ready, let app = chosen else { return }
        progress = CheckProgress()
        guard let run = services.startCheck(app, { [weak self] line in self?.progress.add(line) }) else {
            stage = .failed
            return
        }
        self.run = run
        stage = .checking
        services.checkStarted(app)
        Task { [weak self] in
            let end = await run.waitForEnd()
            guard let self else { return }
            self.services.checkEnded()
            guard self.run === run else { return } // started again since
            self.run = nil
            switch end {
            case .finished(let result?):
                self.stage = .done(result)
                // What muting needs, as it stands now (the last step may offer it).
                if result.setup == nil, let traits = self.traits {
                    self.permissions = await self.services.permissions(app, traits.scriptable)
                }
            case .finished(nil), .failed: self.stage = .failed
            case .stopped: self.stage = .stopped
            case .permissionMissing:
                self.permissionMissingInCheck = true
                self.stage = .allowing
                self.watchPermissions()
            }
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

    /// Muting needs Audio Recording (the last step's Mute It Instead).
    var canMute: Bool { permissions.audio == .allowed }

    /// The last step's Mute It Instead, when no way worked: the app is
    /// muted while other apps play, never paused, and made the player.
    func useMuting() {
        guard let result, result.setup == nil, canMute, let app = chosen else { return }
        let setup = PlayerSetup(bundleID: app.bundleID, name: app.name, appURL: app.url, ways: [.mute])
        services.use(CheckResult(ways: result.ways, setup: setup))
        services.close()
    }

    /// Asks for Audio Recording from the last step, for muting, and follows it.
    func allowMuting() {
        guard let app = chosen, let traits else { return }
        let current = permissions
        Task { [weak self] in
            await self?.services.request(.audioRecording, app, current)
            for _ in 0..<60 {
                guard let self, self.result != nil, !self.canMute else { return }
                self.permissions = await self.services.permissions(app, traits.scriptable)
                await self.services.sleep(.seconds(1))
            }
        }
    }

    /// The last step's Use: keeps what worked and makes the app the player.
    func use() {
        guard let result, result.setup != nil else { return }
        services.use(result)
        services.close()
    }

    /// The window closed: a check under way stops, and nothing is kept.
    func windowClosed() {
        services.closeChooser()
        stopWork()
        run?.stop()
    }

    private func stopWork() {
        work?.cancel()
        work = nil
    }
}
