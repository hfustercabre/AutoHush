import Foundation
import OSLog

// MARK: - Debounce scheduling

protocol PlaybackArbiterDebounceScheduling: Sendable {
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never>
}

struct TaskSleepDebounceScheduler: PlaybackArbiterDebounceScheduling {
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(delay)) }
    }
}

// MARK: - Playback arbiting protocol

protocol PlaybackArbiting: Actor {
    func handleSourceChange(sourceID: String, isPlaying: Bool) async
    /// Whether the player's audio currently comes out of this Mac (as opposed
    /// to another device, e.g. through Spotify Connect).
    func handleLocalPlaybackChange(_ isLocal: Bool) async
}

// MARK: - Playback arbiter
//
// Receives play/stop events from AudioMonitor and decides when to pause
// and resume the music player. Rule: pause when any foreign source starts; resume
// (after debounce) when ALL foreign sources have stopped.
//
// The player's state is pushed in through `handlePlayerStateChange` (from its
// state observer) and cached for status display. The player is only queried
// right before pausing or resuming, so those decisions always use its live
// state.
//
// The player is only paused while its audio plays on this Mac: playback on
// another device (e.g. through Spotify Connect) does not compete with local
// audio.

actor PlaybackArbiter: PlaybackArbiting {
    private let player: any MusicPlayer
    private var configuration: AppConfiguration
    private let debounceScheduler: PlaybackArbiterDebounceScheduling
    private let onPlaybackStateChange: @Sendable (PlaybackState) -> Void
    private let onAudioLevelsNeededChange: @Sendable (Bool) -> Void
    private var publishedAudioLevelsNeeded: Bool?
    private let logger = Logger(category: "PlaybackArbiter")

    private var pausedByUs = false
    private var isShutDown = false
    private var playerState: PlayerState = .unknown
    /// Assumed true until AudioMonitor reports, which it does on its first tick.
    private var playsLocally = true
    private var autoPauseEnabled: Bool
    private var activeSources: Set<String> = []
    private var pendingResumeTask: Task<Void, Never>?
    private var pendingResumeID: UUID?

    /// A resume is retried this often, this far apart, while the player does
    /// not answer: a timed-out query is not the user changing the player.
    static let resumeRetries = 2
    static let resumeRetryDelay: TimeInterval = 1

    init(
        player: any MusicPlayer,
        configuration: AppConfiguration,
        debounceScheduler: PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        autoPauseEnabled: Bool = true,
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.player = player
        self.configuration = configuration
        self.debounceScheduler = debounceScheduler
        self.autoPauseEnabled = autoPauseEnabled
        self.onPlaybackStateChange = onPlaybackStateChange
        self.onAudioLevelsNeededChange = onAudioLevelsNeededChange
    }

    func handleSourceChange(sourceID: String, isPlaying: Bool) async {
        guard !isShutDown, configuration.isMediaSource(sourceID) else { return }

        if isPlaying {
            cancelPendingResume()
            activeSources.insert(sourceID)
            logger.debug("[arbiter] +\(sourceID, privacy: .public) active=\(self.activeSources.sorted().joined(separator: ","), privacy: .public)")
            await pauseMusicIfNeeded()
            publishPlaybackState()
        } else {
            activeSources.remove(sourceID)
            logger.debug("[arbiter] -\(sourceID, privacy: .public) active=\(self.activeSources.sorted().joined(separator: ","), privacy: .public)")
            if activeSources.isEmpty {
                scheduleResume(after: configuration.debounceSeconds)
            } else {
                publishPlaybackState()
            }
        }
    }

    /// Applies new settings; a resume already scheduled keeps its delay.
    func setConfiguration(_ configuration: AppConfiguration) {
        self.configuration = configuration
    }

    /// Turns automatic pausing on or off (the menu's "Auto-Pause Music").
    ///
    /// Off: a pending resume is cancelled and the player, if we paused it, resumes
    /// right away — the user wants it playing alongside the other audio.
    /// On: if another app is already playing, the player is paused as if that app
    /// had just started. Sources keep being tracked while off.
    func setAutoPauseEnabled(_ enabled: Bool) async {
        guard !isShutDown, enabled != autoPauseEnabled else { return }
        autoPauseEnabled = enabled
        logger.debug("[arbiter] auto-pause \(enabled ? "on" : "off", privacy: .public)")
        if enabled {
            if !activeSources.isEmpty { await pauseMusicIfNeeded() }
        } else {
            cancelPendingResume()
            if pausedByUs { await resumeNow() }
        }
        publishPlaybackState()
    }

    /// Called whenever the player reports a new state. If the user resumed,
    /// stopped or quit it while we held it paused, we are no longer
    /// responsible for it and must not resume it later.
    ///
    /// `.unknown` carries no information and is ignored.
    func handlePlayerStateChange(_ state: PlayerState) {
        guard !isShutDown, state != .unknown else { return }
        playerState = state
        if pausedByUs, state != .paused {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) — clearing pausedByUs")
            pausedByUs = false
        }
        publishPlaybackState()
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) {
        guard !isShutDown, isLocal != playsLocally else { return }
        playsLocally = isLocal
        publishPlaybackState()
    }

    /// Queries the player's live state, caches it and publishes the resulting
    /// playback state. Used once at bootstrap to seed the cache.
    @discardableResult
    func refreshPlaybackState() async -> PlayerState {
        let state = await livePlayerState()
        publishPlaybackState()
        return state
    }

    /// Stops all future actions, including an already scheduled resume.
    /// Called when this arbiter is replaced by a new bootstrap.
    func shutdown() {
        isShutDown = true
        cancelPendingResume()
    }

    // MARK: - Private

    private func livePlayerState() async -> PlayerState {
        let state = await player.playerState()
        if state != .unknown { playerState = state }
        return state
    }

    private func cancelPendingResume() {
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        pendingResumeID = nil
    }

    private func pauseMusicIfNeeded() async {
        guard autoPauseEnabled else { return }
        guard playsLocally else {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) is not playing on this Mac — not pausing")
            return
        }
        let state = await livePlayerState()
        guard state == .playing else {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) — not pausing")
            return
        }
        guard !isShutDown, autoPauseEnabled else { return }
        do {
            try await player.pause()
            pausedByUs = true
            playerState = .paused
            logger.debug("[arbiter] \(self.player.name, privacy: .public) paused")
            // Auto-pause was turned off while we were pausing: undo it.
            if !autoPauseEnabled { await resumeNow() }
        } catch {
            logger.error("[arbiter] pause failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleResume(after delay: TimeInterval, retriesLeft: Int = PlaybackArbiter.resumeRetries) {
        cancelPendingResume()
        let id = UUID()
        pendingResumeID = id
        let debounceTask = debounceScheduler.scheduleDebounce(after: delay)
        pendingResumeTask = Task { [weak self] in
            _ = await debounceTask.value
            await self?.resumeIfStillPending(id: id, retriesLeft: retriesLeft)
        }
    }

    private func resumeIfStillPending(id: UUID, retriesLeft: Int) async {
        guard pendingResumeID == id, !isShutDown else { return }
        // With auto-pause off, music we paused comes back even while others play.
        guard activeSources.isEmpty || !autoPauseEnabled else { return }
        guard pausedByUs else {
            publishPlaybackState()
            return
        }
        await resumeNow(unlessSuperseded: id, retriesLeft: retriesLeft)
    }

    /// Resumes the player after re-checking its live state: if the user manually
    /// paused, resumed, or quit it while the source was active, respect
    /// that and do not override their intent. With `id`, gives up when that
    /// pending resume was cancelled or replaced while the player was queried.
    private func resumeNow(unlessSuperseded id: UUID? = nil, retriesLeft: Int = PlaybackArbiter.resumeRetries) async {
        let currentState = await livePlayerState()
        guard !isShutDown, id == nil || pendingResumeID == id else { return }
        if currentState == .unknown, retriesLeft > 0 {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) did not answer — trying the resume again")
            scheduleResume(after: Self.resumeRetryDelay, retriesLeft: retriesLeft - 1)
            return
        }
        guard currentState == .paused else {
            logger.debug("[arbiter] resume skipped — \(self.player.name, privacy: .public) is \(currentState.rawValue, privacy: .public) (user interaction detected)")
            pausedByUs = false
            publishPlaybackState()
            return
        }

        cancelPendingResume()
        pausedByUs = false
        do {
            try await player.play()
            playerState = .playing
            logger.debug("[arbiter] \(self.player.name, privacy: .public) resumed")
        } catch {
            logger.error("[arbiter] resume failed: \(error.localizedDescription, privacy: .public)")
        }
        publishPlaybackState()
    }

    private func publishPlaybackState() {
        onPlaybackStateChange(mapPlaybackState())

        let needed = audioLevelsNeeded
        if needed != publishedAudioLevelsNeeded {
            publishedAudioLevelsNeeded = needed
            onAudioLevelsNeededChange(needed)
        }
    }

    /// Audio levels only matter while they can change a decision: whether to
    /// pause a player playing on this Mac, or when to resume one we paused.
    /// Otherwise the monitor captures nothing (no recording indicator).
    private var audioLevelsNeeded: Bool {
        guard autoPauseEnabled, !isShutDown else { return false }
        return pausedByUs || (playerState == .playing && playsLocally)
    }

    private func mapPlaybackState() -> PlaybackState {
        if pausedByUs, !activeSources.isEmpty { return .pausedByMonitor }
        if playerState == .playing, !playsLocally { return .playingElsewhere }

        switch playerState {
        case .playing:                       return .musicPlaying
        case .paused, .stopped, .notRunning: return .musicIdle
        case .unknown:                       return .unknown
        }
    }
}
