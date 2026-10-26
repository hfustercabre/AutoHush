import Foundation
import os

/// Everything one start creates (see GLOSSARY.md) — arbiter, audio monitor
/// and player observer — wired together, started and torn down as a unit.
/// The engine's front door: the app makes its monitoring only through it,
/// so `AudioMonitor` and `PlaybackArbiter` stay internal (X19, the full
/// check, 2026-10-20).
///
/// Commands to the arbiter (player state changes, auto-pause on/off) and
/// status updates for the menu each travel through a single ordered stream,
/// so neither side can see them out of order.
@MainActor
package final class MonitoringPipeline {
    /// What the engine reports for the menu and Settings.
    package enum StatusUpdate: Sendable {
        case playback(PlaybackState)
        case activeSources([AudioSource])
        case detection(DetectionMode)
        /// AntiDot mode learned how an app tells macOS it plays.
        case learnedAssertions(String, AnnouncedAssertions)
        /// Why the music couldn't be paused, then `nil` once that's over.
        case pauseFailure(MusicPlayerError?)
        /// The player is muted in place of AutoHush's pause (one that didn't
        /// take, a start by itself, or a refused one), then `false` once the
        /// mute is lifted.
        case mutedInstead(Bool)
        /// The last resume was given up (no answer, or its play failed),
        /// then `nil` once that's over.
        case resumeFailure(MusicPlayerError?)
    }

    /// What the app tells the arbiter.
    private enum ArbiterCommand: Sendable {
        case playerState(PlayerState)
        case autoPause(Bool)
        case configuration(AppConfiguration)
        /// With its number (see `PlaybackArbiter.setAsleep`).
        case asleep(Bool, change: Int)
        case resumesHeld(Bool)
        case outputDisconnected
        case tapsAllowed(Bool)
        case retryResume
        case unmuteInstead
    }

    private let arbiter: PlaybackArbiter
    private let monitor: AudioMonitor
    /// Told whether it may tap its sound, when it can (see `allowTaps`).
    private let mutingPlayer: any MutingMusicPlayer?
    /// Whether the player may be muted through a tap (`PlayerMuting`): not
    /// in AntiDot mode.
    private let tapsAllowed: OSAllocatedUnfairLock<Bool>
    private let playerObserver: any PlayerStateObserving
    private let outputDisconnects: any OutputDisconnectWatching
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
    package struct Readers {
        let processes: any AudioProcessSnapshotProviding
        let levelMeter: any AudioLevelMetering?
        let audioCapturePermission: any AudioCapturePermissionChecking
        let powerAssertions: any PowerAssertionReading
        /// When the output in use goes away (Pause on disconnect).
        let outputDisconnects: any OutputDisconnectWatching
        /// Mutes the player with this bundle ID while taps are allowed, in
        /// place of a pause that didn't take, a start by itself, or a refused one.
        let playerMute: @Sendable (String, @escaping @Sendable () -> Bool) -> (any PlayerMuting)?
        /// For the player with this bundle ID: whether the user pressed a
        /// key or clicked in it, while it was already in front, after a
        /// moment (media keys don't count).
        let playerInput: @Sendable (String) -> @Sendable (Date) -> Bool

        package init(
            processes: any AudioProcessSnapshotProviding = HALAudioProcessSnapshotProvider(),
            levelMeter: any AudioLevelMetering? = ProcessTapLevelMeter(),
            audioCapturePermission: any AudioCapturePermissionChecking = TCCAudioCapturePermission(),
            powerAssertions: any PowerAssertionReading = IOKitPowerAssertionReader(),
            outputDisconnects: any OutputDisconnectWatching = CoreAudioOutputDisconnectWatcher(),
            playerMute: @escaping @Sendable (String, @escaping @Sendable () -> Bool) -> (any PlayerMuting)? = {
                ProcessPlayerMute(bundleID: $0, tapsAllowed: $1)
            },
            playerInput: @escaping @Sendable (String) -> @Sendable (Date) -> Bool = { bundleID in
                let input = PlayerInput(bundleID: bundleID)
                return { input.since($0) }
            }
        ) {
            self.playerMute = playerMute
            self.playerInput = playerInput
            self.processes = processes
            self.levelMeter = levelMeter
            self.audioCapturePermission = audioCapturePermission
            self.powerAssertions = powerAssertions
            self.outputDisconnects = outputDisconnects
        }
    }

    /// `hostedApp` names a process's app when its program doesn't (see
    /// `ProcessAudioSourceIdentifier`). `resumesHeld`: it starts with
    /// resumes held (see `holdResumes`). `volumeLeveler` lowers the Mac's
    /// volume as the music resumes after quieter apps (Settings → Behavior):
    /// the app's one, which every monitoring shares.
    package init(
        player: any MusicPlayer,
        hostedApp: @escaping @Sendable (pid_t) -> AudioSource? = { _ in nil },
        configuration: AppConfiguration,
        autoPauseEnabled: Bool,
        resumesHeld: Bool = false,
        ignoredSourceIDs: Set<String>,
        detectionMethod: DetectionMethod,
        learnedAssertions: [String: AnnouncedAssertions],
        volumeLeveler: any ResumeLeveling? = nil,
        readers: Readers = Readers(),
        onStatusUpdate: @escaping @MainActor (StatusUpdate) -> Void
    ) {
        let (statusStream, statusUpdates) = AsyncStream.makeStream(of: StatusUpdate.self)
        let (commandStream, arbiterCommands) = AsyncStream.makeStream(of: ArbiterCommand.self)

        // The arbiter decides when audio levels are needed; the monitor, created
        // after it, captures audio only then.
        let monitorLink = MonitorLink()
        let tapsAllowed = OSAllocatedUnfairLock(initialState: Self.allowsTaps(detectionMethod))
        self.tapsAllowed = tapsAllowed
        let arbiter = PlaybackArbiter(
            player: player,
            configuration: configuration,
            autoPauseEnabled: autoPauseEnabled,
            resumesHeld: resumesHeld,
            onPlaybackStateChange: { statusUpdates.yield(.playback($0)) },
            onAudioLevelsNeededChange: { monitorLink.monitor?.setAudioLevelsNeeded($0) },
            onPausedByUsChange: { monitorLink.monitor?.setMusicPaused($0) },
            volumeLeveler: volumeLeveler,
            resumeOffset: { await monitorLink.monitor?.resumeOffsetDB() },
            onPauseFailure: { statusUpdates.yield(.pauseFailure($0)) },
            onResumeFailure: { statusUpdates.yield(.resumeFailure($0)) },
            hearsPlayer: { since in await monitorLink.monitor?.playerHearing(since: since) ?? .unknown },
            inputToPlayer: readers.playerInput(player.bundleID),
            onMutedInsteadChange: { statusUpdates.yield(.mutedInstead($0)) },
            playerMute: readers.playerMute(player.bundleID) { tapsAllowed.withLock { $0 } },
            tapsAllowed: { tapsAllowed.withLock { $0 } }
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
        mutingPlayer = player as? any MutingMusicPlayer
        Self.allowTaps(for: mutingPlayer, in: detectionMethod)
        self.playerObserver = player.makeStateObserver { [weak monitor] state in
            arbiterCommands.yield(.playerState(state))
            monitor?.setPlayerPlaying(state == .playing)
        }
        self.arbiter = arbiter
        self.monitor = monitor
        self.outputDisconnects = readers.outputDisconnects
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
                    case .resumesHeld(let held): await arbiter.holdResumes(held)
                    case .outputDisconnected: await arbiter.handleOutputDisconnected()
                    case .tapsAllowed(let allowed): await arbiter.setTapsAllowed(allowed)
                    case .retryResume: await arbiter.retryResume()
                    case .unmuteInstead: await arbiter.unmuteInstead()
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
    /// `true` when it took a pause over (`takingOverPause`, and the player is
    /// paused). Started while the Mac sleeps (`asleep`), the arbiter knows it
    /// before any app reaches it; a wake told meanwhile wins, though it may
    /// reach the arbiter first (the changes are numbered).
    @discardableResult
    package func start(takingOverPause: Bool = false, asleep: Bool = false) async -> Bool {
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
        let commands = arbiterCommands
        outputDisconnects.start { commands.yield(.outputDisconnected) }
        return tookOver
    }

    package func stop() {
        guard !isStopped else { return }
        playerObserver.stop()
        monitor.stop()
        outputDisconnects.stop()
        arbiterCommands.finish()
        statusUpdates.finish()
        forwarders.forEach { $0.cancel() }
        let arbiter = arbiter
        shutdown = Task { await arbiter.shutdown() }
    }

    /// Stops, and waits until a faded-down player has its volume back.
    package func stopAndRestoreVolume() async {
        stop()
        await shutdown?.value
    }

    /// Returns once no resume is under way, the music fading back in
    /// included (see `PlaybackArbiter.waitForResume`).
    package func waitForResume() async {
        await arbiter.waitForResume()
    }

    package func setAutoPauseEnabled(_ enabled: Bool) {
        arbiterCommands.yield(.autoPause(enabled))
    }

    /// The Mac goes to sleep, or woke up: see `PlaybackArbiter.setAsleep`.
    package func setAsleep(_ asleep: Bool) {
        sleepChanges += 1
        arbiterCommands.yield(.asleep(asleep, change: sleepChanges))
    }

    /// Holds resumes, or lets them happen again: see
    /// `PlaybackArbiter.holdResumes`.
    package func holdResumes(_ held: Bool) {
        arbiterCommands.yield(.resumesHeld(held))
    }

    /// Try Again on the menu's "Couldn't resume" (`PlaybackArbiter.retryResume`).
    package func retryResume() {
        arbiterCommands.yield(.retryResume)
    }

    /// Unmute on the menu's card, for a player muted in place of its pause
    /// (`PlaybackArbiter.unmuteInstead`).
    package func unmuteInstead() {
        arbiterCommands.yield(.unmuteInstead)
    }

    /// Applies new timings and thresholds live.
    package func setConfiguration(_ configuration: AppConfiguration) {
        monitor.setConfiguration(configuration)
        arbiterCommands.yield(.configuration(configuration))
    }

    package func setDetectionMethod(_ method: DetectionMethod) {
        monitor.setDetectionMethod(method)
        Self.allowTaps(for: mutingPlayer, in: method)
        let allowed = Self.allowsTaps(method)
        tapsAllowed.withLock { $0 = allowed }
        arbiterCommands.yield(.tapsAllowed(allowed)) // a mute standing for a pause is lifted
    }

    /// AntiDot mode promises no audio taps, with either of its ways of
    /// detecting: a player that mutes itself through one (a web app that
    /// refuses to pause) doesn't then, nor listens to itself first.
    private static func allowTaps(for player: any MutingMusicPlayer?, in method: DetectionMethod) {
        player?.allowTaps(Self.allowsTaps(method))
    }

    /// Only while audio levels are measured: AntiDot mode is off.
    static func allowsTaps(_ method: DetectionMethod) -> Bool { !method.isAntiDot }

    package func setIgnoredSources(_ ids: Set<String>) {
        monitor.setIgnoredSources(ids)
    }

    package func activeAudioReport() -> [ActiveAudioReport.Entry] {
        monitor.activeAudioReport()
    }

    /// Returns once what the monitor has seen so far has reached the
    /// arbiter (see `AudioMonitor.eventsDelivered`); tests use it.
    func eventsDelivered() async {
        await monitor.eventsDelivered()
    }
}

/// Lets the arbiter reach the monitor that is created after it.
private final class MonitorLink: @unchecked Sendable {
    weak var monitor: AudioMonitor?
}
