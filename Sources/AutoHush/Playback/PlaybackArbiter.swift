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
    /// Whether Spotify's audio currently comes out of this Mac (as opposed to
    /// another Spotify Connect device).
    func handleSpotifyLocalPlaybackChange(_ isLocal: Bool) async
}

// MARK: - Playback arbiter
//
// Receives play/stop events from AudioMonitor and decides when to pause
// and resume Spotify. Rule: pause when any foreign source starts; resume
// (after debounce) when ALL foreign sources have stopped.
//
// Spotify's state is pushed in through `handleSpotifyStateChange` (from
// Spotify's PlaybackStateChanged notification) and cached for status display.
// Spotify is only queried (via Apple events) right before pausing or resuming, so those
// decisions always use Spotify's live state.
//
// Spotify is only paused while its audio plays on this Mac: playback on
// another Spotify Connect device does not compete with local audio.

actor PlaybackArbiter: PlaybackArbiting {
    private let spotify: any SpotifyControlling
    private var configuration: AppConfiguration
    private let debounceScheduler: PlaybackArbiterDebounceScheduling
    private let onPlaybackStateChange: @Sendable (PlaybackState) -> Void
    private let onAudioLevelsNeededChange: @Sendable (Bool) -> Void
    private var publishedAudioLevelsNeeded: Bool?
    private let logger = Logger(category: "PlaybackArbiter")

    private var pausedByUs = false
    private var isShutDown = false
    private var spotifyState: SpotifyPlayerState = .unknown
    /// Assumed true until AudioMonitor reports, which it does on its first tick.
    private var spotifyPlaysLocally = true
    private var autoPauseEnabled: Bool
    private var activeSources: Set<String> = []
    private var pendingResumeTask: Task<Void, Never>?
    private var pendingResumeID: UUID?

    init(
        spotify: any SpotifyControlling,
        configuration: AppConfiguration,
        debounceScheduler: PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        autoPauseEnabled: Bool = true,
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.spotify = spotify
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
                scheduleResume()
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
    /// Off: a pending resume is cancelled and Spotify, if we paused it, resumes
    /// right away — the user wants it playing alongside the other audio.
    /// On: if another app is already playing, Spotify is paused as if that app
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

    /// Called whenever Spotify reports a new player state. If the user resumed,
    /// stopped or quit Spotify while we held it paused, we are no longer
    /// responsible for it and must not resume it later.
    ///
    /// `.unknown` carries no information and is ignored.
    func handleSpotifyStateChange(_ state: SpotifyPlayerState) {
        guard !isShutDown, state != .unknown else { return }
        spotifyState = state
        if pausedByUs, state != .paused {
            logger.debug("[arbiter] Spotify is \(state.rawValue, privacy: .public) — clearing pausedByUs")
            pausedByUs = false
        }
        publishPlaybackState()
    }

    func handleSpotifyLocalPlaybackChange(_ isLocal: Bool) {
        guard !isShutDown, isLocal != spotifyPlaysLocally else { return }
        spotifyPlaysLocally = isLocal
        publishPlaybackState()
    }

    /// Queries Spotify's live state, caches it and publishes the resulting
    /// playback state. Used once at bootstrap to seed the cache.
    @discardableResult
    func refreshPlaybackState() async -> SpotifyPlayerState {
        let state = await liveSpotifyState()
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

    private func liveSpotifyState() async -> SpotifyPlayerState {
        let state = await spotify.playerState()
        if state != .unknown { spotifyState = state }
        return state
    }

    private func cancelPendingResume() {
        pendingResumeTask?.cancel()
        pendingResumeTask = nil
        pendingResumeID = nil
    }

    private func pauseMusicIfNeeded() async {
        guard autoPauseEnabled else { return }
        guard spotifyPlaysLocally else {
            logger.debug("[arbiter] Spotify is not playing on this Mac — not pausing")
            return
        }
        let state = await liveSpotifyState()
        guard state == .playing else {
            logger.debug("[arbiter] Spotify is \(state.rawValue, privacy: .public) — not pausing")
            return
        }
        guard !isShutDown, autoPauseEnabled else { return }
        do {
            try await spotify.pause()
            pausedByUs = true
            spotifyState = .paused
            logger.debug("[arbiter] Spotify paused")
            // Auto-pause was turned off while we were pausing: undo it.
            if !autoPauseEnabled { await resumeNow() }
        } catch {
            logger.error("[arbiter] pause failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleResume() {
        cancelPendingResume()
        let id = UUID()
        pendingResumeID = id
        let debounceTask = debounceScheduler.scheduleDebounce(after: configuration.debounceSeconds)
        pendingResumeTask = Task { [weak self] in
            _ = await debounceTask.value
            await self?.resumeIfStillPending(id: id)
        }
    }

    private func resumeIfStillPending(id: UUID) async {
        guard pendingResumeID == id, !isShutDown else { return }
        guard activeSources.isEmpty else { return }
        guard pausedByUs else {
            publishPlaybackState()
            return
        }
        await resumeNow(unlessSuperseded: id)
    }

    /// Resumes Spotify after re-checking its live state: if the user manually
    /// paused, resumed, or quit Spotify while the source was active, respect
    /// that and do not override their intent. With `id`, gives up when that
    /// pending resume was cancelled or replaced while Spotify was queried.
    private func resumeNow(unlessSuperseded id: UUID? = nil) async {
        let currentState = await liveSpotifyState()
        guard !isShutDown, id == nil || pendingResumeID == id else { return }
        guard currentState == .paused else {
            logger.debug("[arbiter] resume skipped — Spotify is \(currentState.rawValue, privacy: .public) (user interaction detected)")
            pausedByUs = false
            publishPlaybackState()
            return
        }

        cancelPendingResume()
        pausedByUs = false
        do {
            try await spotify.play()
            spotifyState = .playing
            logger.debug("[arbiter] Spotify resumed")
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
    /// pause a Spotify playing on this Mac, or when to resume one we paused.
    /// Otherwise the monitor captures nothing (no recording indicator).
    private var audioLevelsNeeded: Bool {
        guard autoPauseEnabled, !isShutDown else { return false }
        return pausedByUs || (spotifyState == .playing && spotifyPlaysLocally)
    }

    private func mapPlaybackState() -> PlaybackState {
        if pausedByUs, !activeSources.isEmpty { return .pausedByMonitor }
        if spotifyState == .playing, !spotifyPlaysLocally { return .spotifyPlayingElsewhere }

        switch spotifyState {
        case .playing:                       return .spotifyPlaying
        case .paused, .stopped, .notRunning: return .spotifyIdle
        case .unknown:                       return .unknown
        }
    }
}
