import Foundation
import OSLog

// MARK: - Debounce scheduling

/// Waits before a deferred decision (a resume tried again, or a pause once
/// auto-pause is back on): the real one sleeps, tests complete it by hand.
package protocol PlaybackArbiterDebounceScheduling: Sendable {
    /// A task that finishes after `delay` seconds.
    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never>
}

/// Waits with `Task.sleep`.
package struct TaskSleepDebounceScheduler: PlaybackArbiterDebounceScheduling {
    package func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(delay)) }
    }
}

// MARK: - Playback arbiting protocol

/// Takes AudioMonitor's events. Each call returns promptly: whatever it leads
/// to (a pause with its fade-out) runs on its own, so the next event is never
/// held up by it.
package protocol PlaybackArbiting: Actor {
    func handleSourceChange(sourceID: String, isPlaying: Bool) async
    /// Whether the player's audio currently comes out of this Mac (as opposed
    /// to another device, e.g. through Spotify Connect).
    func handleLocalPlaybackChange(_ isLocal: Bool) async
}

// MARK: - Playback arbiter

/// Decides when to pause and resume the music player. Rule: pause when any
/// foreign source starts; resume when ALL foreign sources have stopped (each
/// counts as stopped once silent for its stop grace), but only music it
/// paused itself.
///
/// The player's state is pushed in through `handlePlayerStateChange` (from its
/// state observer) and cached for status display. The player is only queried
/// right before pausing or resuming, so those decisions always use its live
/// state.
///
/// The player is only paused while its audio plays on this Mac: playback on
/// another device (e.g. through Spotify Connect) does not compete with local
/// audio.
///
/// Pauses and resumes run in tasks of their own (`pauseTask`,
/// `pendingResumeTask`), so events keep arriving while the music fades: a
/// source that stops during the fade-out brings the music back up, and one
/// that starts during a fade-in fades it out again.
package actor PlaybackArbiter: PlaybackArbiting {
    private let player: any MusicPlayer
    /// Fades the player out before pausing and back in after playing.
    private let fader: VolumeFader
    /// True while the music fades out ahead of a pause.
    private var isFadingOut = false
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
    /// A pause waiting for apps tracked while auto-pause was off to be
    /// measured again (see `setAutoPauseEnabled`).
    private var pendingPauseTask: Task<Void, Never>?
    private var pendingPauseID: UUID?
    /// The pause under way: the player's state is checked, then the music
    /// fades out and pauses.
    private var pauseTask: Task<Void, Never>?

    /// A resume is retried this often, this far apart, while the player does
    /// not answer: a timed-out query is not the user changing the player.
    package static let resumeRetries = 2
    package static let resumeRetryDelay: TimeInterval = 1
    /// Once auto-pause is back on, the pause for apps already playing waits
    /// their stop grace plus this: a couple of the monitor's ticks.
    package static let remeasureMargin: TimeInterval = 0.5
    /// After taking over a pause, how long beyond the start confirmation the
    /// monitor, starting afresh, gets to find an app still playing.
    package static let takeOverMargin: TimeInterval = 1.5

    package init(
        player: any MusicPlayer,
        configuration: AppConfiguration,
        debounceScheduler: PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        fadeSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
        autoPauseEnabled: Bool = true,
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in }
    ) {
        self.player = player
        self.fader = VolumeFader(
            player: player,
            fadeOut: configuration.fadeOutDuration,
            fadeIn: configuration.fadeInDuration,
            sleep: fadeSleep
        )
        self.configuration = configuration
        self.debounceScheduler = debounceScheduler
        self.autoPauseEnabled = autoPauseEnabled
        self.onPlaybackStateChange = onPlaybackStateChange
        self.onAudioLevelsNeededChange = onAudioLevelsNeededChange
    }

    /// Records that a source started or stopped. Returns without waiting for
    /// the pause it may start (`waitForPause()` does).
    package func handleSourceChange(sourceID: String, isPlaying: Bool) async {
        guard !isShutDown, configuration.isMediaSource(sourceID) else { return }

        if isPlaying {
            // With auto-pause off, music we paused comes back regardless.
            if autoPauseEnabled { cancelPendingResume() }
            cancelPendingPause() // this app pauses the music now
            activeSources.insert(sourceID)
            logActiveSources(after: "+\(sourceID)")
            // The music may be coming back up after a cancelled fade-out: stop
            // that, so the pause in progress fades out again.
            if isFadingOut { await fader.stopComeback() }
            startPause() // publishes the outcome
        } else {
            activeSources.remove(sourceID)
            logActiveSources(after: "-\(sourceID)")
            if activeSources.isEmpty {
                // Stopped during the fade-out: the music comes back up unpaused.
                if isFadingOut { await fader.cancel() }
                scheduleResume(after: nil)
            } else {
                publishPlaybackState()
            }
        }
    }

    /// Applies new settings.
    package func setConfiguration(_ configuration: AppConfiguration) async {
        self.configuration = configuration
        await fader.setDurations(fadeOut: configuration.fadeOutDuration, fadeIn: configuration.fadeInDuration)
    }

    /// Turns automatic pausing on or off (the menu's "Auto-Pause Music").
    ///
    /// Off: a pending resume is cancelled and the player, if we paused it, resumes
    /// right away — the user wants it playing alongside the other audio.
    /// On: if other apps are already playing, the player is paused once they
    /// have been measured again. Sources keep being tracked while off, but
    /// without audio levels (the monitor captures nothing then), so an app
    /// that only has its output open, such as a muted call, counts as
    /// playing; the monitor drops it within its stop grace.
    package func setAutoPauseEnabled(_ enabled: Bool) async {
        guard !isShutDown, enabled != autoPauseEnabled else { return }
        autoPauseEnabled = enabled
        logger.debug("[arbiter] auto-pause \(enabled ? "on" : "off", privacy: .public)")
        if enabled {
            if !activeSources.isEmpty {
                schedulePause(after: configuration.sourceStopGrace + Self.remeasureMargin)
            }
        } else {
            cancelPendingPause()
            cancelPendingResume()
            if isFadingOut { await fader.cancel() }
            if pausedByUs { scheduleResume(after: nil) }
        }
        publishPlaybackState()
    }

    /// Takes over the pause of the AutoHush that ran before this one, which
    /// quit to install an update while holding the music paused: if the
    /// player is still paused, it counts as paused by this arbiter, so the
    /// music comes back once no other app plays. Apps still playing are found
    /// again first; when none is, the music resumes after the start
    /// confirmation plus `takeOverMargin`.
    package func takeOverPause() async {
        guard !isShutDown else { return }
        let state = await livePlayerState()
        guard !isShutDown, state == .paused else { return }
        pausedByUs = true
        logger.debug("[arbiter] took over the pause of the previous AutoHush")
        publishPlaybackState()
        if activeSources.isEmpty {
            scheduleResume(after: autoPauseEnabled ? configuration.sourceStartConfirmation + Self.takeOverMargin : nil)
        }
    }

    /// Called whenever the player reports a new state. If the user resumed,
    /// stopped or quit it while we held it paused, we are no longer
    /// responsible for it and must not resume it later.
    ///
    /// A report can be stale, though: some players post the state they had
    /// just before the new one (Music, right after our pause: "Playing", then
    /// "Paused"). So a report that would end our pause is checked with the
    /// player first, and ignored while it's still paused.
    ///
    /// `.unknown` carries no information and is ignored.
    package func handlePlayerStateChange(_ state: PlayerState) async {
        guard !isShutDown, state != .unknown else { return }
        guard pausedByUs, state != .paused else {
            playerState = state
            publishPlaybackState()
            return
        }
        let live = await livePlayerState()
        guard !isShutDown else { return }
        if live == .paused {
            logger.debug("[arbiter] \(self.player.name, privacy: .public) reported \(state.rawValue, privacy: .public) but is paused — keeping pausedByUs")
        } else {
            if live == .unknown { playerState = state } // no answer: the report stands
            if pausedByUs {
                logger.debug("[arbiter] \(self.player.name, privacy: .public) is \(self.playerState.rawValue, privacy: .public) — clearing pausedByUs")
                pausedByUs = false
            }
        }
        publishPlaybackState()
    }

    package func handleLocalPlaybackChange(_ isLocal: Bool) {
        guard !isShutDown, isLocal != playsLocally else { return }
        playsLocally = isLocal
        publishPlaybackState()
    }

    /// Queries the player's live state, caches it and publishes the resulting
    /// playback state. Used once at bootstrap to seed the cache.
    @discardableResult
    package func refreshPlaybackState() async -> PlayerState {
        let state = await livePlayerState()
        publishPlaybackState()
        return state
    }

    /// Stops all future actions, including an already scheduled resume.
    /// Called when this arbiter is replaced by a new bootstrap.
    package func shutdown() async {
        isShutDown = true
        cancelPendingPause()
        cancelPendingResume()
        await fader.abandon() // never leave the music faded down
    }

    // MARK: - Private

    private func logActiveSources(after change: String) {
        logger.debug("[arbiter] \(change, privacy: .public) active=\(self.activeSources.sorted().joined(separator: ","), privacy: .public)")
    }

    private func livePlayerState() async -> PlayerState {
        let state = await player.playerState()
        if state != .unknown { playerState = state }
        return state
    }

    /// Pauses the music in a task of its own, unless a pause is already
    /// under way: that one sees the new sources too.
    private func startPause() {
        guard pauseTask == nil else { return }
        pauseTask = Task {
            await pauseMusicIfNeeded()
            pauseTask = nil
            publishPlaybackState()
        }
    }

    /// Waits until no pause is under way. Tests use it to see a pause's outcome.
    package func waitForPause() async {
        while let pauseTask { await pauseTask.value }
    }

    /// Pauses after `delay` if other apps are still playing then. A newer
    /// pause, an app starting or auto-pause going off calls it off.
    private func schedulePause(after delay: TimeInterval) {
        cancelPendingPause()
        let id = UUID()
        pendingPauseID = id
        let wait = debounceScheduler.scheduleDebounce(after: delay)
        pendingPauseTask = Task { [weak self] in
            _ = await wait.value
            await self?.pauseIfStillPending(id: id)
        }
    }

    private func pauseIfStillPending(id: UUID) {
        guard pendingPauseID == id else { return }
        pendingPauseTask = nil
        pendingPauseID = nil
        if !activeSources.isEmpty { startPause() }
    }

    private func cancelPendingPause() {
        pendingPauseTask?.cancel()
        pendingPauseTask = nil
        pendingPauseID = nil
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
            if await muteIfPlayingAnyway(saying: state) { return }
            logger.debug("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) — not pausing")
            return
        }
        // Things may have changed while the player answered.
        guard !isShutDown, autoPauseEnabled, !isFadingOut, !activeSources.isEmpty else { return }
        isFadingOut = true
        let paused: Bool
        do {
            paused = try await fader.fadeOutAndPause()
        } catch MusicPlayerError.stillLearning {
            isFadingOut = false
            logger.debug("[arbiter] \(self.player.name, privacy: .public)'s controls aren't learned yet — not pausing")
            return
        } catch {
            isFadingOut = false
            logger.error("[arbiter] pause failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        isFadingOut = false
        guard paused else {
            logger.debug("[arbiter] pause called off during the fade-out")
            // Another app may have started while the music came back up.
            if !activeSources.isEmpty, !isShutDown { await pauseMusicIfNeeded() }
            return
        }
        pausedByUs = true
        playerState = .paused
        logger.debug("[arbiter] \(self.player.name, privacy: .public) paused")
        if !autoPauseEnabled {
            // Auto-pause was turned off while we were pausing: undo it.
            scheduleResume(after: nil)
        } else if activeSources.isEmpty, !isShutDown {
            // Every app stopped while we were pausing, too late to call it off.
            scheduleResume(after: nil)
        }
    }

    /// A player that says it's paused or stopped while it plays here (a web
    /// app's ad, during which its button reads "Play") is muted instead, if it
    /// can be: that's our pause, and resuming lifts the mute.
    private func muteIfPlayingAnyway(saying state: PlayerState) async -> Bool {
        guard state == .paused || state == .stopped, let muting = player as? any MutingMusicPlayer,
              await muting.muteIfPlayingAnyway() else { return false }
        pausedByUs = true
        playerState = .paused
        logger.debug("[arbiter] \(self.player.name, privacy: .public) is \(state.rawValue, privacy: .public) but can be heard — muted")
        // Things may have changed while it was measured.
        if !isShutDown, !autoPauseEnabled || activeSources.isEmpty { scheduleResume(after: nil) }
        return true
    }

    /// Resumes the music in a task of its own: after `delay`, or right away
    /// when it is `nil`. A newer resume or a source starting calls it off.
    private func scheduleResume(after delay: TimeInterval?, retriesLeft: Int = PlaybackArbiter.resumeRetries) {
        cancelPendingResume()
        let id = UUID()
        pendingResumeID = id
        let debounceTask = delay.map { debounceScheduler.scheduleDebounce(after: $0) }
        pendingResumeTask = Task { [weak self] in
            _ = await debounceTask?.value
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
        await resumeNow(id: id, retriesLeft: retriesLeft)
    }

    /// Resumes the player after re-checking its live state: if the user manually
    /// paused, resumed, or quit it while the source was active, respect
    /// that and do not override their intent. Gives up when the pending
    /// resume `id` was cancelled or replaced while the player was queried.
    private func resumeNow(id: UUID, retriesLeft: Int) async {
        let currentState = await livePlayerState()
        guard !isShutDown, pendingResumeID == id else { return }
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

        // Forget the pending resume without cancelling it: this may be running
        // inside it, and a cancelled task would rush the fade-in's steps.
        pendingResumeTask = nil
        pendingResumeID = nil
        pausedByUs = false
        do {
            try await fader.playAndFadeIn()
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
