import Foundation

/// Everything one bootstrap creates — arbiter, audio monitor and player
/// observer — wired together, started and torn down as a unit.
///
/// Commands to the arbiter (player state changes, auto-pause on/off) and
/// status updates for the menu each travel through a single ordered stream,
/// so neither side can see them out of order.
@MainActor
final class MonitoringPipeline {
    enum StatusUpdate: Sendable {
        case playback(PlaybackState)
        case activeSources([AudioSource])
        case detection(DetectionMode)
        /// An app was seen announcing playback with a power assertion.
        case announcingApp(String)
    }

    private enum ArbiterCommand: Sendable {
        case playerState(PlayerState)
        case autoPause(Bool)
        case configuration(AppConfiguration)
    }

    private let arbiter: PlaybackArbiter
    private let monitor: AudioMonitor
    private let playerObserver: any PlayerStateObserving
    private let arbiterCommands: AsyncStream<ArbiterCommand>.Continuation
    private let statusUpdates: AsyncStream<StatusUpdate>.Continuation
    private let forwarders: [Task<Void, Never>]
    private var isStopped = false

    init(
        player: any MusicPlayer,
        configuration: AppConfiguration,
        autoPauseEnabled: Bool,
        ignoredSourceIDs: Set<String>,
        detectionMethod: DetectionMethod,
        announcingSourceIDs: Set<String>,
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
            onAudioLevelsNeededChange: { monitorLink.monitor?.setAudioLevelsNeeded($0) }
        )
        let monitor = AudioMonitor(
            configuration: configuration,
            arbiter: arbiter,
            audioCapturePermission: TCCAudioCapturePermission(),
            sourceIdentifier: ProcessAudioSourceIdentifier(),
            ignoredSourceIDs: ignoredSourceIDs,
            powerAssertions: IOKitPowerAssertionReader(),
            announcingSourceIDs: announcingSourceIDs,
            onAnnouncingSourceLearned: { statusUpdates.yield(.announcingApp($0)) },
            detectionMethod: detectionMethod,
            audioLevelsNeeded: false, // until the arbiter knows the player's state
            onActiveSourcesChange: { statusUpdates.yield(.activeSources($0)) },
            onDetectionModeChange: { statusUpdates.yield(.detection($0)) }
        )
        monitorLink.monitor = monitor
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

    /// Observes the player, seeds the arbiter with its live state, then
    /// starts audio monitoring — unless `stop()` was called in the meantime.
    func start() async {
        // Observe before seeding so no state change can slip in between.
        playerObserver.start()
        let initialState = await arbiter.refreshPlaybackState()
        guard !isStopped else { return }
        monitor.setPlayerPlaying(initialState == .playing)
        monitor.start()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        playerObserver.stop()
        monitor.stop()
        arbiterCommands.finish()
        statusUpdates.finish()
        forwarders.forEach { $0.cancel() }
        let arbiter = arbiter
        Task { await arbiter.shutdown() }
    }

    /// Stops, and waits until a faded-down player has its volume back.
    func stopAndRestoreVolume() async {
        stop()
        await arbiter.shutdown()
    }

    func setAutoPauseEnabled(_ enabled: Bool) {
        arbiterCommands.yield(.autoPause(enabled))
    }

    /// Applies new timings and thresholds live.
    func setConfiguration(_ configuration: AppConfiguration) {
        monitor.setConfiguration(configuration)
        arbiterCommands.yield(.configuration(configuration))
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        monitor.setDetectionMethod(method)
    }

    func setIgnoredSources(_ ids: Set<String>) {
        monitor.setIgnoredSources(ids)
    }

    func activeAudioReport() -> [String] {
        monitor.activeAudioReport()
    }
}

/// Lets the arbiter reach the monitor that is created after it.
private final class MonitorLink: @unchecked Sendable {
    weak var monitor: AudioMonitor?
}
