import Foundation
import OSLog
import AutoHushKit

/// A player's monitoring, as the player session runs it: a
/// `MonitoringPipeline`; tests stand in for it.
@MainActor
protocol SessionMonitoring: HeldMonitoring {
    /// Starts it, taking over a pause handed over when `takingOverPause`;
    /// `true` when it took one over (see `MonitoringPipeline.start`).
    @discardableResult
    func start(takingOverPause: Bool, asleep: Bool) async -> Bool
    func setAsleep(_ asleep: Bool)
    func setConfiguration(_ configuration: AppConfiguration)
    func setDetectionMethod(_ method: DetectionMethod)
    func activeAudioReport() -> [ActiveAudioReport.Entry]
}

extension MonitoringPipeline: SessionMonitoring {}

/// What the chosen player's monitoring follows from the user's settings.
struct MonitoringSettings: Equatable {
    /// Auto-Pause is on now: neither turned off nor snoozed.
    var autoPause: Bool
    /// The bundle IDs of the apps the user ignores.
    var ignored: Set<String>
    var timings: TimingSettings
    var detection: DetectionMethod
}

/// The chosen player, from its start until AutoHush quits (see
/// GLOSSARY.md): it starts the player, tries again after a failed start,
/// checks again that AutoHush may still control it, runs its monitoring
/// with the monitoring settings, and keeps the held pauses and the
/// hand-over. Choosing a player, noticing whether it's installed and
/// learning a web app's controls happen outside, and call it; the menu and
/// Settings show its state.
@MainActor
final class PlayerSession {
    /// What the session knows, for the menu and Settings.
    struct State: Equatable {
        /// Whether the chosen player's monitoring runs, and if not, why;
        /// `nil` while no player is chosen.
        var health: AppHealthState?
        var playback: PlaybackState = .unknown
        var detection: DetectionMode = .pending
        /// The apps playing right now, ignored ones included, by name; none
        /// unless monitoring runs.
        var activeSources: [AudioSource] = []
        /// Why the player couldn't be controlled, while that's what the menu
        /// says: a start that failed with an error, or a pause that failed.
        var controlError: ControlError?
    }

    /// What a new monitoring starts with.
    struct MonitoringSetup {
        let configuration: AppConfiguration
        let settings: MonitoringSettings
        let learnedAssertions: [String: AnnouncedAssertions]
    }

    /// Makes a player's monitoring, whose updates go to the closure.
    typealias MakeMonitoring = @MainActor (
        any MusicPlayer, MonitoringSetup, @escaping @MainActor (MonitoringPipeline.StatusUpdate) -> Void
    ) -> any SessionMonitoring

    /// After a failed start, starting is tried again by itself: while a
    /// permission is missing every `permissionInterval`, since it may be
    /// granted any moment; otherwise after `delays.lowerBound`, doubling up
    /// to `delays.upperBound`, so a busy or hung player isn't flooded with
    /// requests. macOS announces neither. A player that isn't running is
    /// started on when it opens, and one that isn't installed when it's back.
    struct Retries {
        var permissionInterval: TimeInterval = 3
        var delays: ClosedRange<TimeInterval> = 5...60
    }

    /// Startup checks after the player launches are retried this often, this
    /// far apart, while it is not ready to answer.
    static let startupRetries = 3
    static let startupRetryDelay: TimeInterval = 2
    /// A restart for an update or by another copy takes seconds: an older
    /// hand-over is stale.
    static let pauseHandoverMaxAge: TimeInterval = 60

    private(set) var state: State {
        didSet { if state != oldValue { didChange(state) } }
    }
    /// Called each time `state` changes.
    var didChange: @MainActor (State) -> Void = { _ in }
    /// What monitoring follows; each change goes to the monitorings that
    /// follow it. Held pauses follow Auto-Pause and the ignored apps only.
    var settings: MonitoringSettings {
        didSet { follow(settings, from: oldValue) }
    }
    /// The music player AutoHush pauses and resumes; `nil` until one is chosen.
    private(set) var player: (any MusicPlayer)?

    private let players: MusicPlayerCatalog
    private let preferences: Preferences
    private let monitoringMaker: MakeMonitoring
    private let locateApp: PlayerOption.Locate
    private let retries: Retries
    private let logger = Logger(category: "PlayerSession")

    /// The chosen player's monitoring, while it runs.
    private var monitoring: (any SessionMonitoring)?
    /// Which monitoring an update comes from: the current one has this.
    private var monitoringToken = UUID()
    /// The monitoring of players AutoHush held paused when the user chose
    /// another, running on to end those pauses (`HeldPauses`).
    private let heldPauses = HeldPauses()
    /// Each start has its number; one that finds a newer one started gives up.
    private var startGeneration = 0
    private var retryTimer: Timer?
    /// Failed starts in a row, for the delay before the next one.
    private var failedStarts = 0
    /// The problem of the last failed start, logged as an error once; its
    /// repeats (every few seconds while a permission is missing) go to the
    /// debug log.
    private(set) var loggedStartupProblem: String?
    /// The check that AutoHush may still control the player, while one runs:
    /// see `checkAccess()`.
    private var accessCheck: Task<Void, Never>?
    /// The first monitoring that starts may take over a pause handed over by
    /// the AutoHush before this one; later ones don't.
    private var pauseHandoverChecked = false
    /// Between the Mac going to sleep and waking up: a monitoring started
    /// meanwhile (the player relaunched in a dark wake) knows it too.
    private var isAsleep = false
    /// AutoHush is quitting: nothing starts any more (see `quit`).
    private var hasQuit = false

    init(
        player: (any MusicPlayer)?,
        players: MusicPlayerCatalog,
        preferences: Preferences,
        settings: MonitoringSettings,
        makeMonitoring: @escaping MakeMonitoring,
        locateApp: @escaping PlayerOption.Locate,
        retries: Retries = Retries()
    ) {
        self.player = player
        self.players = players
        self.preferences = preferences
        self.settings = settings
        monitoringMaker = makeMonitoring
        self.locateApp = locateApp
        self.retries = retries
        state = State(health: player == nil ? nil : .starting)
    }

    /// Makes `MonitoringPipeline`s, whose processes are named by `hostedApp`
    /// when their program doesn't say (a Safari web app).
    static func pipelines(hostedApp: @escaping @Sendable (pid_t) -> AudioSource?) -> MakeMonitoring {
        { player, setup, onUpdate in
            MonitoringPipeline(
                player: player,
                hostedApp: hostedApp,
                configuration: setup.configuration,
                autoPauseEnabled: setup.settings.autoPause,
                ignoredSourceIDs: setup.settings.ignored,
                detectionMethod: setup.settings.detection,
                learnedAssertions: setup.learnedAssertions,
                onStatusUpdate: onUpdate
            )
        }
    }

    // MARK: - What the app tells it

    /// At launch, once the copies of AutoHush opened before this one have
    /// quit: the players they held paused get their monitoring again, then
    /// the chosen player starts.
    func launch(now: Date = Date()) {
        startHeldPauses(handedOverHeldPlayers(now: now))
        if player != nil { requestStart() }
    }

    /// The user chose `newPlayer`: a pause AutoHush holds on the player it
    /// leaves is still its own to end, so that player's monitoring runs on
    /// for it (`heldPauses`), and a player held paused that is chosen again
    /// is taken back by its new monitoring. `nil`: no player is chosen any
    /// more (it was deleted), and nothing runs.
    func choose(_ newPlayer: (any MusicPlayer)?) {
        guard let newPlayer else {
            player = nil
            startGeneration += 1 // a start under way gives up
            cancelRetry()
            tearDownMonitoring()
            setHealth(nil)
            return
        }
        holdPause(for: newPlayer.bundleID)
        player = newPlayer
        failedStarts = 0
        setHealth(.starting)
        requestStart()
    }

    /// Starts over at once, with the waits between automatic tries back to
    /// the shortest: Retry on the menu's card, or the player installed again.
    func retry() {
        failedStarts = 0
        setHealth(.starting)
        requestStart()
    }

    /// An app opened: the chosen player is controlled afresh; it may not
    /// answer yet while it finishes starting up.
    func playerLaunched(_ bundleID: String) {
        guard let player, bundleID == player.bundleID else { return }
        logger.debug("\(player.name, privacy: .public) launch detected — starting again")
        failedStarts = 0
        setHealth(.starting)
        requestStart(retries: Self.startupRetries)
    }

    /// Whether the chosen player is installed, as AutoHush last found: once
    /// it's gone, nothing runs and the health says so; once it's back, it's
    /// controlled afresh.
    func setPlayerInstalled(_ installed: Bool) {
        guard let player else { return }
        let notInstalled = AppHealthState.playerNotInstalled(player.name)
        if installed {
            if state.health == notInstalled { retry() }
        } else if state.health != notInstalled {
            logger.notice("\(player.name, privacy: .public) is not installed")
            startGeneration += 1 // a start under way gives up
            cancelRetry()        // and none is tried until it's back
            tearDownMonitoring()
            setHealth(notInstalled)
        }
    }

    /// Checks again that AutoHush may still control the player, when it
    /// matters: another app starts playing, or the menu opens. macOS doesn't
    /// announce a permission taken away while monitoring runs, and the player
    /// then only reads as unknown, so nothing would be paused, silently. A
    /// missing permission starts over as at launch: the menu asks for it, and
    /// monitoring starts again by itself once it's given back.
    func checkAccess() {
        guard state.health == .ready, let player, accessCheck == nil else { return }
        let generation = startGeneration
        accessCheck = Task { [weak self] in
            defer { self?.accessCheck = nil }
            do {
                try await player.verifyControlAccess()
            } catch {
                guard let self, generation == self.startGeneration else { return }
                switch error as? MusicPlayerError {
                case .automationPermissionDenied?, .accessibilityPermissionDenied?:
                    self.logger.error("Lost control of \(player.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    self.requestStart()
                default:
                    break // the player quit or didn't answer: monitoring follows those
                }
            }
        }
    }

    /// Music AutoHush paused stays paused after the Mac sleeps: the
    /// arbiter forgets the pause as the Mac falls asleep, when the other
    /// apps' sound stops too, and decides nothing until it's awake.
    func setAsleep(_ asleep: Bool) {
        guard asleep != isAsleep else { return }
        isAsleep = asleep
        // As any pause: after sleeping it's the user's (decision S2).
        if asleep { heldPauses.stopAll() }
        logger.info("The Mac \(asleep ? "goes to sleep" : "woke up", privacy: .public)")
        monitoring?.setAsleep(asleep)
    }

    /// AutoHush quits: the pauses it holds are handed over, so an AutoHush
    /// opened next (an update, another copy, a quick reopen) resumes the
    /// music once the other apps stop. Later than `pauseHandoverMaxAge`,
    /// it's ignored, and so is one for another player than the one chosen by
    /// then. Every monitoring then stops, a faded-down player getting its
    /// volume back first: the task returned ends once that's done; `nil`
    /// when nothing runs. Nothing starts from then on, and a start under way
    /// gives up: a monitoring it made would run on with nothing to stop it.
    func quit(now: Date = Date()) -> Task<Void, Never>? {
        hasQuit = true
        startGeneration += 1
        cancelRetry()
        handOverPauses(now: now)
        let monitoring = self.monitoring
        guard monitoring != nil || !heldPauses.isEmpty else { return nil }
        self.monitoring = nil
        let heldPauses = heldPauses
        return Task {
            await monitoring?.stopAndRestoreVolume()
            await heldPauses.stopAndRestoreAll()
        }
    }

    /// AutoHush holds a pause, the chosen player's or a held one.
    var isHoldingPause: Bool {
        state.playback == .pausedByMonitor || !heldPauses.isEmpty
    }

    /// The apps with sound as the monitoring sees them, for Diagnostics.
    func activeAudioReport() -> [ActiveAudioReport.Entry] {
        monitoring?.activeAudioReport() ?? []
    }

    // MARK: - Starting

    private func requestStart(retries: Int = 0) {
        Task { await start(retriesLeft: retries) }
    }

    /// Errors that mean the player is not ready yet rather than a lasting problem.
    nonisolated static func isTransientStartupError(_ error: any Error) -> Bool {
        switch error as? MusicPlayerError {
        case .playerNotResponding, .playerNotRunning: return true
        default:                                         return false
        }
    }

    private func start(retriesLeft: Int = 0) async {
        guard !hasQuit else { return }
        startGeneration += 1
        let generation = startGeneration
        cancelRetry() // this start takes its place
        tearDownMonitoring()
        guard let player else {
            setHealth(nil) // nothing to control yet
            return
        }
        // Where the player says, else where macOS knows it, as the players are listed.
        guard player.installedURL ?? locateApp(player.bundleID) != nil else {
            setHealth(.playerNotInstalled(player.name))
            return
        }

        do {
            try await player.verifyControlAccess()
        } catch {
            guard generation == startGeneration else { return }
            if retriesLeft > 0, Self.isTransientStartupError(error) {
                logger.debug("\(player.name, privacy: .public) is not ready yet (\(error.localizedDescription, privacy: .public)) — retrying")
                try? await Task.sleep(for: .seconds(Self.startupRetryDelay))
                guard generation == startGeneration else { return } // Retry or another launch took over
                await start(retriesLeft: retriesLeft - 1)
                return
            }
            let problem = "\(player.name): \(error.localizedDescription)"
            if problem == loggedStartupProblem {
                logger.debug("Still can't control \(problem, privacy: .public)")
            } else {
                logger.error("Can't control \(problem, privacy: .public)")
                loggedStartupProblem = problem
            }
            // The line says AutoHush can't control it: the menu tells why.
            var failed = state
            switch error as? MusicPlayerError {
            case .playerCommandFailed?, .stillLearning?, nil: failed.controlError = ControlError(error, player: player.name)
            default: failed.controlError = nil
            }
            state = failed
            setHealth(AppHealthState(startupError: error, playerName: player.name))
            retryLater(after: error)
            return
        }
        // A newer start (Retry, player relaunch) began while we awaited.
        guard generation == startGeneration else { return }

        let token = UUID()
        monitoringToken = token
        let monitoring = makeMonitoring(for: player, token: token)
        self.monitoring = monitoring
        // Both asked every time: each answers once.
        let takesBack = heldPauses.takesBack(player.bundleID)
        let takesOver = takesOverPause()
        await monitoring.start(takingOverPause: takesOver || takesBack, asleep: isAsleep)
        guard generation == startGeneration else { return }
        failedStarts = 0
        loggedStartupProblem = nil
        var started = state
        started.controlError = nil
        state = started
        setHealth(.ready)
    }

    /// Tries starting again after `error`, unless an event will: see `Retries`.
    private func retryLater(after error: any Error) {
        let delay: TimeInterval
        switch error as? MusicPlayerError {
        case .playerNotRunning:
            return // started on when the player opens
        case .automationPermissionDenied, .accessibilityPermissionDenied:
            delay = retries.permissionInterval
        default:
            failedStarts += 1
            delay = Self.retryDelay(afterFailedStarts: failedStarts, delays: retries.delays)
        }
        cancelRetry()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.retryTimer = nil
                self?.requestStart()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        retryTimer = timer
    }

    private func cancelRetry() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    /// The wait before starting again after `failedStarts` failed starts in a
    /// row: the range's lower bound, doubling up to its upper bound.
    nonisolated static func retryDelay(afterFailedStarts failedStarts: Int, delays: ClosedRange<TimeInterval>) -> TimeInterval {
        min(delays.lowerBound * pow(2, Double(max(failedStarts - 1, 0))), delays.upperBound)
    }

    // MARK: - Monitoring

    /// Monitoring for `player`, whose updates come with `token`: the current
    /// one's are applied; a held pause's stay with `heldPauses`.
    private func makeMonitoring(for player: any MusicPlayer, token: UUID) -> any SessionMonitoring {
        let setup = MonitoringSetup(configuration: configuration(for: player), settings: settings,
                                    learnedAssertions: preferences.playbackAssertions)
        return monitoringMaker(player, setup) { [weak self, token] update in
            guard let self, !self.heldPauses.takes(update, from: token) else { return }
            self.apply(update)
        }
    }

    /// The engine's configuration: the user's timings, and the player, whose
    /// own audio never counts as another app playing.
    private func configuration(for player: (any MusicPlayer)?) -> AppConfiguration {
        var configuration = AppConfiguration(timings: settings.timings)
        configuration.musicPlayerBundleID = player?.bundleID
        return configuration
    }

    private func apply(_ update: MonitoringPipeline.StatusUpdate) {
        switch update {
        case .playback(let playback):
            state.playback = playback
        case .activeSources(let sources):
            let othersStarted = state.activeSources.isEmpty && !sources.isEmpty
            // Recorded first: Settings → Apps lists them as the state shows.
            preferences.recordSeen(sources)
            state.activeSources = sources
            if othersStarted { checkAccess() }
        case .detection(let mode):
            state.detection = mode
        case .learnedAssertions(let id, let assertions):
            preferences.playbackAssertions[id] = assertions
        case .pauseFailure(let error):
            state.controlError = error.map { ControlError($0, player: player?.name ?? "") }
        }
    }

    /// Each setting that changed goes to the monitorings that follow it.
    private func follow(_ settings: MonitoringSettings, from old: MonitoringSettings) {
        if settings.autoPause != old.autoPause {
            monitoring?.setAutoPauseEnabled(settings.autoPause)
            heldPauses.setAutoPauseEnabled(settings.autoPause)
        }
        if settings.ignored != old.ignored {
            monitoring?.setIgnoredSources(settings.ignored)
            heldPauses.setIgnoredSources(settings.ignored)
        }
        if settings.timings != old.timings { monitoring?.setConfiguration(configuration(for: player)) }
        if settings.detection != old.detection { monitoring?.setDetectionMethod(settings.detection) }
    }

    /// Without a monitoring nothing is known about the music: a state it left
    /// behind would otherwise hand over a pause that no longer exists, or
    /// keep automatic updates from ever finding a quiet moment.
    private func tearDownMonitoring() {
        monitoring?.stop()
        monitoring = nil
        var stopped = state
        stopped.playback = .unknown
        stopped.detection = .pending
        state = stopped
    }

    /// The health, and the apps playing, which none are unless it's ready.
    private func setHealth(_ health: AppHealthState?) {
        var changed = state
        changed.health = health
        if health != .ready { changed.activeSources = [] }
        state = changed
    }

    // MARK: - Held pauses and the hand-over

    /// The user chooses `bundleID`: see `choose(_:)`.
    private func holdPause(for bundleID: String) {
        if heldPauses.choose(bundleID, leaving: player?.bundleID, current: monitoring, token: monitoringToken,
                             holdsPause: state.playback == .pausedByMonitor) {
            monitoring = nil // left running by the next start
        }
    }

    /// Hands the pauses AutoHush holds over to the AutoHush opened next: the
    /// chosen player's, and those of players held paused when another was
    /// chosen.
    private func handOverPauses(now: Date) {
        let holdsChosen = state.playback == .pausedByMonitor
        guard holdsChosen || !heldPauses.isEmpty else { return }
        preferences.pauseHandover = PauseHandover(at: now, player: holdsChosen ? player?.bundleID : nil,
                                                  holdsChosen: holdsChosen, held: heldPauses.bundleIDs)
    }

    /// At launch: the players held paused when the AutoHush before this one
    /// quit, recently, other than the chosen one, whose own monitoring takes
    /// its pause back (`takesOverPause`); read once.
    private func handedOverHeldPlayers(now: Date) -> [String] {
        guard let handover = preferences.pauseHandover, !handover.held.isEmpty,
              (0...Self.pauseHandoverMaxAge).contains(now.timeIntervalSince(handover.at)) else { return [] }
        let chosen = player?.bundleID
        preferences.pauseHandover = PauseHandover(at: handover.at, player: handover.player, holdsChosen: handover.holdsChosen,
                                                  held: handover.held.filter { $0 == chosen })
        return handover.held.filter { $0 != chosen }
    }

    /// Players held paused get their monitoring again, whatever the chosen
    /// player's does: it takes their pause over and ends it as it would have.
    private func startHeldPauses(_ bundleIDs: [String]) {
        for bundleID in bundleIDs {
            guard let held = players.player(bundleID: bundleID) else { continue }
            let token = UUID()
            let monitoring = makeMonitoring(for: held, token: token)
            heldPauses.keep(monitoring, token: token, bundleID: bundleID, awaitingTakeOver: true)
            Task { [weak self, isAsleep] in
                // Played or quit by the user meanwhile: nothing to end.
                if await !monitoring.start(takingOverPause: true, asleep: isAsleep) { self?.heldPauses.drop(token) }
            }
        }
    }

    /// Whether monitoring takes over a pause handed over by the AutoHush before
    /// this one, at most `pauseHandoverMaxAge` before `now`, and for the
    /// player chosen now: the player may have changed meanwhile (one that
    /// didn't say, from AutoHush 0.8.2 and earlier, counts). Only the first
    /// monitoring asks; it starts after other copies have quit, so their
    /// hand-over is in by then.
    private func takesOverPause(now: Date = Date()) -> Bool {
        guard !pauseHandoverChecked else { return false }
        pauseHandoverChecked = true
        guard let handover = preferences.pauseHandover else { return false }
        preferences.pauseHandover = nil
        guard (0...Self.pauseHandoverMaxAge).contains(now.timeIntervalSince(handover.at)) else { return false }
        // Held paused then, and chosen now: its own pause, back.
        if let chosen = player?.bundleID, handover.held.contains(chosen) { return true }
        guard handover.holdsChosen else { return false }
        if let paused = handover.player, paused != player?.bundleID { return false }
        return true
    }
}
