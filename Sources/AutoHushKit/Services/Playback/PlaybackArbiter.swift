import Foundation
import OSLog

/// Decides when to pause and resume the music player. Rule: pause when any
/// foreign source starts; resume when ALL foreign sources have stopped (each
/// counts as stopped once silent for its stop grace), but only music it
/// paused itself, or found paused just as an app started (see
/// `takeOverPauseOfStartingApp`).
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
    let player: any MusicPlayer
    /// Fades the player out before pausing and back in after playing.
    let fader: VolumeFader
    /// True while the music fades out ahead of a pause.
    var isFadingOut = false
    private var configuration: AppConfiguration
    let debounceScheduler: PlaybackArbiterDebounceScheduling
    let onPlaybackStateChange: @Sendable (PlaybackState) -> Void
    let onAudioLevelsNeededChange: @Sendable (Bool) -> Void
    /// Why the music couldn't be paused, then `nil` once that's over.
    private let onPauseFailure: @Sendable (MusicPlayerError?) -> Void
    /// The last pause failed, while other apps play: the music plays on.
    /// Over once they stop, a pause works, or the player stops playing.
    var pauseFailure: MusicPlayerError? {
        didSet { if pauseFailure != oldValue { onPauseFailure(pauseFailure) } }
    }
    var publishedAudioLevelsNeeded: Bool?
    let logger = Logger(category: "PlaybackArbiter")

    var pausedByUs = false
    /// When the player was seen to stop playing here, as far as the arbiter
    /// knows: it went from playing on this Mac to paused. `nil` while it plays.
    var stoppedPlayingAt: Date?
    /// The latest app to start playing: when it was first heard, and when it
    /// counted as playing.
    var latestStart: (heard: Date, counted: Date)?
    let clock: @Sendable () -> Date
    var isShutDown = false
    /// While the Mac sleeps, nothing is paused or resumed (see `setAsleep`).
    var isAsleep = false
    /// A pause held when the Mac went to sleep, forgotten: the player is
    /// told once the Mac is awake.
    var forgotPauseInSleep = false
    /// The number of the latest sleep or wake applied (see `setAsleep`).
    private var sleepChange = 0
    var playerState: PlayerState = .unknown
    /// Assumed true until AudioMonitor reports, which it does on its first tick.
    var playsLocally = true
    var autoPauseEnabled: Bool
    var activeSources: Set<String> = []
    var pendingResumeTask: Task<Void, Never>?
    var pendingResumeID: UUID?
    /// The resume under way: the player plays and fades back in
    /// (`waitForResume`).
    var resumeTask: Task<Void, Never>?
    /// A pause waiting for apps tracked while auto-pause was off to be
    /// measured again (see `setAutoPauseEnabled`).
    var pendingPauseTask: Task<Void, Never>?
    var pendingPauseID: UUID?
    /// The pause under way: the player's state is checked, then the music
    /// fades out and pauses.
    var pauseTask: Task<Void, Never>?
    /// The debounce the pending resume and pause wait on before they run;
    /// `nil` for one that runs at once (`waitUntilIdle`).
    var pendingResumeWait: Task<Void, Never>?
    var pendingPauseWait: Task<Void, Never>?

    /// A resume is retried this often, this far apart, while the player does
    /// not answer, or doesn't do what it was told (a page that didn't follow
    /// its Play button): a timed-out query is not the user changing the player.
    package static let resumeRetries = 2
    package static let resumeRetryDelay: TimeInterval = 1
    /// Once auto-pause is back on, the pause for apps already playing waits
    /// their stop grace plus this: a couple of the monitor's ticks.
    package static let remeasureMargin: TimeInterval = 0.5
    /// After taking over a pause, how long beyond the start confirmation the
    /// monitor, starting afresh, gets to find an app still playing.
    package static let takeOverMargin: TimeInterval = 1.5
    /// The monitor hears an app up to a couple of its ticks after the app's
    /// sound starts (a new app's levels come from the next tick): a pause seen
    /// up to this long before the app was first heard may still be its doing.
    package static let hearingDelay: TimeInterval = 0.5
    /// An app that pauses other players does it as it starts (VLC, 0.3 s
    /// after, measured): a pause up to this long after the app was first
    /// heard may be its doing. A later one, while the app isn't counted as
    /// playing yet (3 s for sound without video in AntiDot mode), is the user's.
    package static let startPauseWindow: TimeInterval = 1
    /// A check of the player this long at most after an app counted as
    /// playing is the one that app's start called for, and may find a pause
    /// it made (`takeOverPauseOfStartingApp`).
    package static let startCheckWindow: TimeInterval = 2

    package init(
        player: any MusicPlayer,
        configuration: AppConfiguration,
        debounceScheduler: PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        fadeSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() },
        autoPauseEnabled: Bool = true,
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in },
        onPauseFailure: @escaping @Sendable (MusicPlayerError?) -> Void = { _ in }
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
        self.clock = clock
        self.autoPauseEnabled = autoPauseEnabled
        self.onPlaybackStateChange = onPlaybackStateChange
        self.onAudioLevelsNeededChange = onAudioLevelsNeededChange
        self.onPauseFailure = onPauseFailure
    }

    /// Records that a source started or stopped. Returns without waiting for
    /// the pause it may start (`waitForPause()` does).
    package func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date? = nil) async {
        guard !isShutDown, configuration.isMediaSource(sourceID) else { return }

        if isPlaying {
            if let heardSince { latestStart = (heardSince, clock()) }
            // With auto-pause off, music we paused comes back regardless.
            if autoPauseEnabled { cancelPendingResume() }
            cancelPendingPause() // this app pauses the music now
            activeSources.insert(sourceID)
            logActiveSources(after: "+\(sourceID)")
            guard !isAsleep else {
                publishPlaybackState()
                return
            }
            // The music may be coming back up after a cancelled fade-out: stop
            // that, so the pause in progress fades out again.
            if isFadingOut { await fader.stopComeback() }
            startPause() // publishes the outcome
        } else {
            activeSources.remove(sourceID)
            logActiveSources(after: "-\(sourceID)")
            if isAsleep {
                publishPlaybackState()
            } else if activeSources.isEmpty {
                pauseFailure = nil // nothing to pause for any more
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

    /// Turns automatic pausing on or off (the menu's "Auto-Pause" switch).
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
            pauseFailure = nil
            cancelPendingPause()
            cancelPendingResume()
            if isFadingOut { await fader.cancel() }
            if pausedByUs { scheduleResume(after: nil) }
        }
        publishPlaybackState()
    }

    /// The Mac goes to sleep (`true`) or is awake again (`false`).
    ///
    /// The other apps' sound stops as the Mac falls asleep, which isn't them
    /// ending: a pause AutoHush holds is forgotten, so the music stays paused
    /// after waking, as music players keep it after a sleep. While asleep
    /// nothing is paused or resumed (a web page can't be pressed then); once
    /// awake, apps playing pause the music as usual.
    ///
    /// `change` numbers the changes as they happened, when they can arrive
    /// by more than one way: one older than the latest applied comes late,
    /// and is ignored.
    package func setAsleep(_ asleep: Bool, change: Int? = nil) async {
        if let change {
            guard change > sleepChange else { return }
            sleepChange = change
        }
        guard !isShutDown, asleep != isAsleep else { return }
        isAsleep = asleep
        if asleep {
            pauseFailure = nil
            cancelPendingPause()
            cancelPendingResume()
            if pausedByUs {
                pausedByUs = false
                forgotPauseInSleep = true
                logger.debug("[arbiter] the Mac sleeps: \(self.player.name, privacy: .public) stays paused")
            }
        } else {
            logger.debug("[arbiter] the Mac is awake")
            if forgotPauseInSleep, let muting = player as? any MutingMusicPlayer { await muting.forgetPause() }
            forgotPauseInSleep = false
            if autoPauseEnabled, !activeSources.isEmpty { startPause() }
        }
        publishPlaybackState()
    }

    /// Takes over the pause of the AutoHush that ran before this one, which
    /// quit to install an update while holding the music paused: if the
    /// player is still paused, it counts as paused by this arbiter, so the
    /// music comes back once no other app plays. Apps still playing are found
    /// again first; when none is, the music resumes after the start
    /// confirmation plus `takeOverMargin`. `false` when there was no pause to
    /// take over: the player isn't paused.
    @discardableResult
    package func takeOverPause() async -> Bool {
        // Handed over while the Mac sleeps: forgotten, as any pause then.
        guard !isShutDown, !isAsleep else { return false }
        let state = await livePlayerState()
        guard !isShutDown, state == .paused else { return false }
        pausedByUs = true
        logger.debug("[arbiter] took over the pause of the previous AutoHush")
        publishPlaybackState()
        if activeSources.isEmpty {
            scheduleResume(after: autoPauseEnabled ? configuration.sourceStartConfirmation + Self.takeOverMargin : nil)
        }
        return true
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
        noteStoppedPlaying(state)
        if state != .playing { pauseFailure = nil } // the user paused or stopped it
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
        if !isLocal { pauseFailure = nil } // it isn't heard here any more
        publishPlaybackState()
    }

    /// Queries the player's live state, caches it and publishes the resulting
    /// playback state. Used once as monitoring starts, to seed the cache.
    @discardableResult
    package func refreshPlaybackState() async -> PlayerState {
        let state = await livePlayerState()
        publishPlaybackState()
        return state
    }

    /// Stops all future actions, including an already scheduled resume.
    /// Called as its monitoring stops: a new start replaces it, or AutoHush quits.
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

    func livePlayerState() async -> PlayerState {
        let state = await player.playerState()
        if state != .unknown {
            noteStoppedPlaying(state)
            playerState = state
        }
        return state
    }

    /// Notes when the player stops playing here (`stoppedPlayingAt`), from a
    /// state just learned and the one known until then. A pause on another
    /// device (through Spotify Connect) isn't noted: it's no concern here.
    private func noteStoppedPlaying(_ state: PlayerState) {
        switch state {
        case .paused:
            if playerState == .playing { stoppedPlayingAt = playsLocally ? clock() : nil }
        case .playing, .stopped, .notRunning:
            stoppedPlayingAt = nil
        case .unknown:
            break
        }
    }
}
