import Foundation
import AutoHushKit

/// Everything one bootstrap creates — arbiter, audio monitor and player
/// observer — wired together, started and torn down as a unit.
///
/// Commands to the arbiter (player state changes, auto-pause on/off) and
/// status updates for the menu each travel through a single ordered stream,
/// so neither side can see them out of order.
@MainActor
final class MonitoringPipeline {
    /// What the engine reports for the menu and Settings.
    enum StatusUpdate: Sendable {
        case playback(PlaybackState)
        case activeSources([AudioSource])
        case detection(DetectionMode)
        /// AntiDot mode learned how an app tells macOS it plays.
        case learnedAssertions(String, AnnouncedAssertions)
        /// Why the music couldn't be paused, then `nil` once that's over.
        case pauseFailure(MusicPlayerError?)
    }

    /// What the app tells the arbiter.
    private enum ArbiterCommand: Sendable {
        case playerState(PlayerState)
        case autoPause(Bool)
        case configuration(AppConfiguration)
        /// With its number (see `PlaybackArbiter.setAsleep`).
        case asleep(Bool, change: Int)
    }

    private let arbiter: PlaybackArbiter
    private let monitor: AudioMonitor
    /// Told whether it may tap its sound, when it can (see `allowTaps`).
    private let tappingPlayer: (any TappingMusicPlayer)?
    private let playerObserver: any PlayerStateObserving
    private let arbiterCommands: AsyncStream<ArbiterCommand>.Continuation
    private let statusUpdates: AsyncStream<StatusUpdate>.Continuation
    private let forwarders: [Task<Void, Never>]
    /// Started by `stop()`: the arbiter stopping, which sets back a faded volume.
    private var shutdown: Task<Void, Never>?
    /// Numbers each sleep and wake told to the arbiter, which reach it by two
    /// ways (directly from `start`, and through the commands).
    private var sleepChanges = 0
    private var isStopped: Bool { shutdown != nil }

    /// What the audio monitor reads from macOS; tests stand in for it.
    struct Readers {
        var processes: any AudioProcessSnapshotProviding = HALAudioProcessSnapshotProvider()
        var levelMeter: (any AudioLevelMetering)? = ProcessTapLevelMeter()
        var audioCapturePermission: any AudioCapturePermissionChecking = TCCAudioCapturePermission()
        var powerAssertions: any PowerAssertionReading = IOKitPowerAssertionReader()
    }

    /// `hostedApp` names a process's app when its program doesn't (see
    /// `ProcessAudioSourceIdentifier`).
    init(
        player: any MusicPlayer,
        hostedApp: @escaping @Sendable (pid_t) -> AudioSource? = { _ in nil },
        configuration: AppConfiguration,
        autoPauseEnabled: Bool,
        ignoredSourceIDs: Set<String>,
        detectionMethod: DetectionMethod,
        learnedAssertions: [String: AnnouncedAssertions],
        readers: Readers = Readers(),
        onStatusUpdate: @escaping @MainActor (StatusUpdate) -> Void
    ) {
        let (statusStream, statusUpdates) = AsyncStream.makeStream(of: StatusUpdate.self)
        let (commandStream, arbiterCommands) = AsyncStream.makeStream(of: ArbiterCommand.self)

        // The arbiter decides when audio levels are needed; the monitor, created
        // after it, captures audio only then.
        let monitorLink = MonitorLink()
        let arbiter = PlaybackArbiter(
            player: player,
            configuration: configuration,
            autoPauseEnabled: autoPauseEnabled,
            onPlaybackStateChange: { statusUpdates.yield(.playback($0)) },
            onAudioLevelsNeededChange: { monitorLink.monitor?.setAudioLevelsNeeded($0) },
            onPauseFailure: { statusUpdates.yield(.pauseFailure($0)) }
        )
        let monitor = AudioMonitor(
            configuration: configuration,
            arbiter: arbiter,
            snapshotProvider: readers.processes,
            levelMeter: readers.levelMeter,
            audioCapturePermission: readers.audioCapturePermission,
            sourceIdentifier: ProcessAudioSourceIdentifier(hostedApp: hostedApp),
            ignoredSourceIDs: ignoredSourceIDs,
            powerAssertions: readers.powerAssertions,
            learnedAssertions: learnedAssertions,
            onAssertionsLearned: { statusUpdates.yield(.learnedAssertions($0, $1)) },
            detectionMethod: detectionMethod,
            audioLevelsNeeded: false, // until the arbiter knows the player's state
            onActiveSourcesChange: { statusUpdates.yield(.activeSources($0)) },
            onDetectionModeChange: { statusUpdates.yield(.detection($0)) }
        )
        monitorLink.monitor = monitor
        tappingPlayer = player as? any TappingMusicPlayer
        Self.allowTaps(for: tappingPlayer, in: detectionMethod)
        self.playerObserver = player.makeStateObserver { [weak monitor] state in
            arbiterCommands.yield(.playerState(state))
            monitor?.setPlayerPlaying(state == .playing)
        }
        self.arbiter = arbiter
        self.monitor = monitor
        self.arbiterCommands = arbiterCommands
        self.statusUpdates = statusUpdates
        self.forwarders = [
            Task {
                for await command in commandStream {
                    switch command {
                    case .playerState(let state): await arbiter.handlePlayerStateChange(state)
                    case .autoPause(let enabled):  await arbiter.setAutoPauseEnabled(enabled)
                    case .configuration(let configuration): await arbiter.setConfiguration(configuration)
                    case .asleep(let asleep, let change): await arbiter.setAsleep(asleep, change: change)
                    }
                }
            },
            Task { @MainActor in
                for await update in statusStream {
                    onStatusUpdate(update)
                }
            },
        ]
    }

    /// Observes the player, seeds the arbiter with its live state, takes over
    /// a pause handed over by the AutoHush before this one when asked to, then
    /// starts audio monitoring — unless `stop()` was called in the meantime.
    /// Started while the Mac sleeps (`asleep`), the arbiter knows it before
    /// any app reaches it; a wake told meanwhile wins, though it may reach
    /// the arbiter first (the changes are numbered).
    /// Starts monitoring; `true` when it took a pause over (`takingOverPause`
    /// and the player is paused).
    @discardableResult
    func start(takingOverPause: Bool = false, asleep: Bool = false) async -> Bool {
        if asleep {
            sleepChanges += 1
            await arbiter.setAsleep(true, change: sleepChanges)
        }
        // Observe before seeding so no state change can slip in between.
        playerObserver.start()
        let initialState = await arbiter.refreshPlaybackState()
        guard !isStopped else { return false }
        // Before monitoring starts, so the apps it finds see the pause as ours.
        let tookOver = takingOverPause ? await arbiter.takeOverPause() : false
        guard !isStopped else { return tookOver }
        monitor.setPlayerPlaying(initialState == .playing)
        monitor.start()
        return tookOver
    }

    func stop() {
        guard !isStopped else { return }
        playerObserver.stop()
        monitor.stop()
        arbiterCommands.finish()
        statusUpdates.finish()
        forwarders.forEach { $0.cancel() }
        let arbiter = arbiter
        shutdown = Task { await arbiter.shutdown() }
    }

    /// Stops, and waits until a faded-down player has its volume back.
    func stopAndRestoreVolume() async {
        stop()
        await shutdown?.value
    }

    func setAutoPauseEnabled(_ enabled: Bool) {
        arbiterCommands.yield(.autoPause(enabled))
    }

    /// The Mac goes to sleep, or woke up: see `PlaybackArbiter.setAsleep`.
    func setAsleep(_ asleep: Bool) {
        sleepChanges += 1
        arbiterCommands.yield(.asleep(asleep, change: sleepChanges))
    }

    /// Applies new timings and thresholds live.
    func setConfiguration(_ configuration: AppConfiguration) {
        monitor.setConfiguration(configuration)
        arbiterCommands.yield(.configuration(configuration))
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        monitor.setDetectionMethod(method)
        Self.allowTaps(for: tappingPlayer, in: method)
    }

    /// AntiDot mode promises no audio taps, with either of its ways of
    /// detecting: a player that mutes itself through one (a web app that
    /// refuses to pause) doesn't then, nor listens to itself first.
    private static func allowTaps(for player: (any TappingMusicPlayer)?, in method: DetectionMethod) {
        player?.allowTaps(Self.allowsTaps(method))
    }

    /// Only while audio levels are measured: AntiDot mode is off.
    static func allowsTaps(_ method: DetectionMethod) -> Bool { method == .audioLevels }

    func setIgnoredSources(_ ids: Set<String>) {
        monitor.setIgnoredSources(ids)
    }

    func activeAudioReport() -> [ActiveAudioReport.Entry] {
        monitor.activeAudioReport()
    }
}

/// Lets the arbiter reach the monitor that is created after it.
private final class MonitorLink: @unchecked Sendable {
    weak var monitor: AudioMonitor?
}
