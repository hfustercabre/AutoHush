import Foundation
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
    func activeAudioReport() -> [ActiveAudioReport.Entry]
    /// Listens to the player: see `MonitoringPipeline.checkPlayerHeard`.
    func checkPlayerHeard()
}

extension MonitoringPipeline: SessionMonitoring {}

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
        /// The player is muted in place of AutoHush's pause (one that didn't
        /// take, a start by itself, or a refused one): the menu says Muted.
        var mutedInstead = false
    }

    /// What a new monitoring starts with.
    struct MonitoringSetup {
        let configuration: AppConfiguration
        let settings: MonitoringSettings
        let learnedAssertions: [String: AnnouncedAssertions]
        /// It starts with resumes held (see `PlayerSession.holdResumes`).
        var resumesHeld: Bool
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
        /// Waits between the startup checks after the player launches
        /// (`startupRetryDelay`); tests stand in for it.
        var startupWait: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    }

    /// Startup checks after the player launches are retried this often, this
    /// far apart, while it is not ready to answer.
    static let startupRetries = 3
    static let startupRetryDelay: TimeInterval = 2
    /// A restart for an update or by another copy takes seconds: an older
    /// hand-over is stale.
    static let pauseHandoverMaxAge: TimeInterval = 60

    var state: State {
        didSet { if state != oldValue { didChange(state) } }
    }
    /// Called each time `state` changes.
    var didChange: @MainActor (State) -> Void = { _ in }
    /// What monitoring follows; each change goes to the monitorings that
    /// follow it. Held pauses follow Auto-Pause, the ignored apps and the
    /// detection method, not the timings.
    var settings: MonitoringSettings {
        didSet { follow(settings, from: oldValue) }
    }
    /// The media player AutoHush pauses and resumes; `nil` until one is chosen.
    var player: any MusicPlayer?

    let players: MusicPlayerCatalog
    let preferences: Preferences
    let monitoringMaker: MakeMonitoring
    let locateApp: PlayerOption.Locate
    let retries: Retries
    let logger = AutoHushLogger(category: "PlayerSession")

    /// The chosen player's monitoring, while it runs.
    var monitoring: any SessionMonitoring?
    /// Which monitoring an update comes from: the current one has this, and
    /// none once it's torn down.
    var monitoringToken = UUID()
    /// The monitoring of players AutoHush held paused when the user chose
    /// another, running on to end those pauses (`HeldPauses`).
    let heldPauses = HeldPauses()
    /// Players no longer chosen, released once their held pause is over.
    var leftPlayers: [String: any MusicPlayer] = [:]
    /// Each start has its number; one that finds a newer one started gives up.
    var startGeneration = 0
    /// The starts requested and not over yet (`requestStart`).
    var startTasks: [UUID: Task<Void, Never>] = [:]
    var retryTimer: Timer?
    /// Failed starts in a row, for the delay before the next one.
    var failedStarts = 0
    /// The problem of the last failed start, logged as an error once; its
    /// repeats (every few seconds while a permission is missing) go to the
    /// debug log.
    var loggedStartupProblem: String?
    /// The check that AutoHush may still control the player, while one runs:
    /// see `checkAccess()`.
    var accessCheck: Task<Void, Never>?
    /// The first monitoring that starts may take over a pause handed over by
    /// the AutoHush before this one; later ones don't.
    var pauseHandoverChecked = false
    /// Between the Mac going to sleep and waking up: a monitoring started
    /// meanwhile (the player relaunched in a dark wake) knows it too.
    var isAsleep = false
    /// While resumes are held (`holdResumes`): a monitoring started meanwhile
    /// starts held too.
    var resumesHeld = false
    /// AutoHush is quitting: nothing starts any more (see `quit`).
    var hasQuit = false
    /// The last start found the chosen player not running: until it opens,
    /// its monitoring runs only to list the apps playing, while Auto-Pause
    /// is on (`listenUntilPlayerOpens`).
    var waitsForPlayerToOpen = false

    init(
        player: any MusicPlayer?,
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
        heldPauses.onEnded = { [weak self] bundleID in
            guard let self, let left = self.leftPlayers.removeValue(forKey: bundleID) else { return }
            self.releaseLeft(left)
        }
    }

    /// Makes `MonitoringPipeline`s, whose processes are named by `hostedApp`
    /// when their program doesn't say (a Safari web app). Each reads macOS
    /// through readers of its own, from `readers`; tests stand in for them.
    /// All share `volumeLeveler`, the app's one: a pause held as another
    /// player is chosen never lowers the Mac's volume over the new one's.
    static func pipelines(
        hostedApp: @escaping @Sendable (pid_t) -> AudioSource?,
        volumeLeveler: any ResumeLeveling? = nil,
        readers: @escaping @MainActor () -> MonitoringPipeline.Readers = { MonitoringPipeline.Readers() }
    ) -> MakeMonitoring {
        { player, setup, onUpdate in
            MonitoringPipeline(
                player: player,
                hostedApp: hostedApp,
                configuration: setup.configuration,
                autoPauseEnabled: setup.settings.autoPause,
                resumesHeld: setup.resumesHeld,
                ignoredSourceIDs: setup.settings.ignored,
                detectionMethod: setup.settings.detection,
                learnedAssertions: setup.learnedAssertions,
                volumeLeveler: volumeLeveler,
                readers: readers(),
                onStatusUpdate: onUpdate
            )
        }
    }
}
