import Foundation

/// Decides when to pause and resume the media player. Rule: pause when any
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
actor PlaybackArbiter: PlaybackArbiting {
    let player: any MusicPlayer
    /// Fades the player out before pausing and back in after playing.
    let fader: VolumeFader
    /// True while the music fades out ahead of a pause.
    var isFadingOut = false
    var configuration: AppConfiguration
    let debounceScheduler: PlaybackArbiterDebounceScheduling
    let onPlaybackStateChange: @Sendable (PlaybackState) -> Void
    let onAudioLevelsNeededChange: @Sendable (Bool) -> Void
    /// Whether the music is paused by us now, for its loudness and the
    /// apps' (`AudioMonitor.setMusicPaused`).
    let onPausedByUsChange: @Sendable (Bool) -> Void
    /// Lowers the Mac's volume as the music resumes after quieter apps, by
    /// `resumeOffset` (Settings → Advanced, `levelsMusic`).
    let volumeLeveler: (any ResumeLeveling)?
    let resumeOffset: @Sendable () async -> Float?
    /// The token of the volume this arbiter lowered for its music
    /// (`ResumeLeveling.lower`), until it's put back: as the music pauses
    /// again, or the arbiter shuts down. The leveler is the app's one, so
    /// another player's lowering is never put back from here.
    var levelLowered: UUID?
    /// The resume under way, or waiting to try again, lowered the volume
    /// (`levelLowered`): once it ends without the music playing, it's put
    /// back (`putBackResumeLevel`).
    var resumeLowered = false
    var publishedPausedByUs: Bool?
    /// Why the music couldn't be paused, then `nil` once that's over.
    private let onPauseFailure: @Sendable (MusicPlayerError?) -> Void
    /// The last pause failed, while other apps play: the music plays on.
    /// Over once they stop, a pause works, or the player stops playing.
    var pauseFailure: MusicPlayerError? {
        didSet { if pauseFailure != oldValue { onPauseFailure(pauseFailure) } }
    }
    var publishedAudioLevelsNeeded: Bool?
    let logger = AutoHushLogger(category: "PlaybackArbiter")

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
    /// While held, nothing paused by us is resumed (see `holdResumes`).
    var resumesHeld: Bool
    var playerState: PlayerState = .unknown
    /// Assumed true until AudioMonitor reports, which it does on its first tick.
    var playsLocally = true
    var autoPauseEnabled: Bool
    var activeSources: Set<String> = []
    /// The apps playing with their microphone on (calls).
    var callSources: Set<String> = []
    /// A call came during our pause (or the fade-out before it): with
    /// `AppConfiguration.staysPausedAfterCalls`, the music isn't resumed.
    var callDuringPause = false
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
    /// Pending resumes and pauses called off while their task still runs,
    /// by their ID, each with its debounce: the task ends on its own once
    /// that's over, finding it was called off (`pendingTaskEnded`). For
    /// `waitUntilIdle`, so a test sees that nothing more happens.
    var calledOff: [UUID: (task: Task<Void, Never>, wait: Task<Void, Never>?)] = [:]
    /// How long an app must play, at most, before the monitor counts it, as
    /// it last said (`handleStartConfirmationChange`); `nil` until it says.
    var longestStartConfirmation: TimeInterval?
    /// A pause taken over (`takeOverPause`) while its resume waits for the
    /// monitor to find an app still playing: when, and that resume.
    var takenOver: (at: Date, resume: UUID)?

    /// A resume is retried this often, this far apart, while the player does
    /// not answer, or doesn't do what it was told (a page that didn't follow
    /// its Play button): a timed-out query is not the user changing the player.
    static let resumeRetries = 2
    static let resumeRetryDelay: TimeInterval = 1
    /// Once auto-pause is back on, the pause for apps already playing waits
    /// their stop grace plus this: a couple of the monitor's ticks.
    static let remeasureMargin: TimeInterval = 0.5
    /// After taking over a pause, how long the monitor, starting afresh, gets
    /// beyond the longest start it applies to find an app still playing.
    static let takeOverMargin: TimeInterval = 1.5
    /// The monitor hears an app up to a couple of its ticks after the app's
    /// sound starts (a new app's levels come from the next tick): a pause seen
    /// up to this long before the app was first heard may still be its doing.
    static let hearingDelay: TimeInterval = 0.5
    /// An app that pauses other players does it as it starts (VLC, 0.3 s
    /// after, measured): a pause up to this long after the app was first
    /// heard may be its doing. A later one, while the app isn't counted as
    /// playing yet (3 s for sound without video in AntiDot mode), is the user's.
    static let startPauseWindow: TimeInterval = 1
    /// A check of the player this long at most after an app counted as
    /// playing is the one that app's start called for, and may find a pause
    /// it made (`takeOverPauseOfStartingApp`).
    static let startCheckWindow: TimeInterval = 2

    init(
        player: any MusicPlayer,
        configuration: AppConfiguration,
        debounceScheduler: PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        fadeSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() },
        autoPauseEnabled: Bool = true,
        resumesHeld: Bool = false,
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in },
        onPausedByUsChange: @escaping @Sendable (Bool) -> Void = { _ in },
        volumeLeveler: (any ResumeLeveling)? = nil,
        resumeOffset: @escaping @Sendable () async -> Float? = { nil },
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
        self.resumesHeld = resumesHeld
        self.onPlaybackStateChange = onPlaybackStateChange
        self.onAudioLevelsNeededChange = onAudioLevelsNeededChange
        self.onPausedByUsChange = onPausedByUsChange
        self.volumeLeveler = volumeLeveler
        self.resumeOffset = resumeOffset
        self.onPauseFailure = onPauseFailure
    }

    /// Records that a source started or stopped. Returns without waiting for
    /// the pause it may start (`waitForPause()` does).
    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date? = nil) async {
        guard !isShutDown, configuration.isMediaSource(sourceID) else { return }

        if isPlaying {
            if let heardSince { latestStart = (heardSince, clock()) }
            // With auto-pause off, music we paused comes back regardless.
            if autoPauseEnabled { cancelPendingResume() }
            cancelPendingPause() // this app pauses the music now
            activeSources.insert(sourceID)
            logActiveSources(after: "\(sourceID) started playing")
            noteCalls()
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
            logActiveSources(after: "\(sourceID) stopped playing")
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

    func handleCallChange(sourceID: String, inCall: Bool) async {
        guard !isShutDown else { return }
        if inCall { callSources.insert(sourceID) } else { callSources.remove(sourceID) }
        logger.info("[arbiter] \(sourceID, privacy: .public) \(inCall ? "is in a call (its microphone is on)" : "is no longer in a call", privacy: .public)")
        noteCalls()
    }

    /// Notes a call among the apps playing while the music is paused by us,
    /// or fades out to be.
    func noteCalls() {
        guard pausedByUs || isFadingOut, !callDuringPause, !callSources.isDisjoint(with: activeSources) else { return }
        callDuringPause = true
        logger.info("[arbiter] a call came during the pause")
    }

    /// Applies new settings.
    func setConfiguration(_ configuration: AppConfiguration) async {
        self.configuration = configuration
        if !configuration.levelsMusic {
            volumeLeveler?.restoreNow() // whoever lowered it: the setting is off for all
            levelLowered = nil
            resumeLowered = false
        }
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
    func setAutoPauseEnabled(_ enabled: Bool) async {
        guard !isShutDown, enabled != autoPauseEnabled else { return }
        autoPauseEnabled = enabled
        logger.info("[arbiter] Auto-Pause \(enabled ? "on" : "off", privacy: .public)")
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
    /// after waking, as media players keep it after a sleep. While asleep
    /// nothing is paused or resumed (a web page can't be pressed then); once
    /// awake, apps playing pause the music as usual.
    ///
    /// `change` numbers the changes as they happened, when they can arrive
    /// by more than one way: one older than the latest applied comes late,
    /// and is ignored.
    func setAsleep(_ asleep: Bool, change: Int? = nil) async {
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
                logger.info("[arbiter] the Mac sleeps: \(self.player.name, privacy: .public) stays paused")
            }
        } else {
            logger.info("[arbiter] the Mac is awake")
            if forgotPauseInSleep, let muting = player as? any MutingMusicPlayer { await muting.forgetPause() }
            forgotPauseInSleep = false
            if autoPauseEnabled, !activeSources.isEmpty { startPause() }
        }
        publishPlaybackState()
    }

    /// Holds every resume (`true`), or lets them happen again (`false`).
    /// While Add an App checks an app, playing and pausing it for minutes,
    /// music its sound paused would otherwise come back in each gap, fading
    /// in and out. Pausing goes on as usual, so music that plays still
    /// pauses when an app starts; a player we didn't pause is never touched.
    /// Released, music we paused resumes as it would have: at once when no
    /// other app plays (or Auto-Pause is off), otherwise once they stop.
    func holdResumes(_ held: Bool) {
        guard !isShutDown, held != resumesHeld else { return }
        resumesHeld = held
        logger.debug("[arbiter] resumes \(held ? "held" : "no longer held", privacy: .public)")
        if held {
            cancelPendingResume() // one checking on the player calls itself off
        } else if pausedByUs, !isAsleep, activeSources.isEmpty || !autoPauseEnabled {
            scheduleResume(after: nil)
        }
        publishPlaybackState()
    }

    /// Takes over the pause of the AutoHush that ran before this one, which
    /// quit to install an update while holding the music paused: if the
    /// player is still paused, it counts as paused by this arbiter, so the
    /// music comes back once no other app plays. Apps still playing are found
    /// again first; when none is, the music resumes after the longest start
    /// the monitor applies (3 s for sound without video in AntiDot mode)
    /// plus `takeOverMargin`. `false` when there was no pause to take over:
    /// the player isn't paused.
    @discardableResult
    func takeOverPause() async -> Bool {
        // Handed over while the Mac sleeps: forgotten, as any pause then.
        guard !isShutDown, !isAsleep else { return false }
        let state = await livePlayerState()
        guard !isShutDown, state == .paused else { return false }
        pausedByUs = true
        logger.info("[arbiter] took over the pause of the previous AutoHush")
        publishPlaybackState()
        if activeSources.isEmpty {
            if autoPauseEnabled { scheduleTakenOverResume(from: clock()) } else { scheduleResume(after: nil) }
        }
        return true
    }

    /// The monitor says how long an app must play, at most, before it
    /// counts. A pause taken over before it said (it starts after the
    /// takeover) waits that long for apps still playing.
    func handleStartConfirmationChange(_ longest: TimeInterval) {
        guard !isShutDown else { return }
        let known = startConfirmation
        longestStartConfirmation = longest
        if longest != known, let takenOver, takenOver.resume == pendingResumeID {
            scheduleTakenOverResume(from: takenOver.at)
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
    func handlePlayerStateChange(_ state: PlayerState) async {
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
                logger.info("[arbiter] \(self.player.name, privacy: .public) is \(self.playerState.rawValue, privacy: .public): the user took it over, it won’t be resumed")
                pausedByUs = false
            }
        }
        publishPlaybackState()
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) {
        guard !isShutDown, isLocal != playsLocally else { return }
        playsLocally = isLocal
        if !isLocal { pauseFailure = nil } // it isn't heard here any more
        publishPlaybackState()
    }

    /// Queries the player's live state, caches it and publishes the resulting
    /// playback state. Used once as monitoring starts, to seed the cache.
    @discardableResult
    func refreshPlaybackState() async -> PlayerState {
        let state = await livePlayerState()
        publishPlaybackState()
        return state
    }

    /// Stops all future actions, including an already scheduled resume.
    /// Called as its monitoring stops: a new start replaces it, or AutoHush quits.
    func shutdown() async {
        isShutDown = true
        cancelPendingPause()
        cancelPendingResume()
        await fader.abandon() // never leave the music faded down
        // Nor the Mac's volume lowered, unless another monitoring lowered it.
        if let levelLowered { volumeLeveler?.restoreNow(lowered: levelLowered) }
        levelLowered = nil
        resumeLowered = false
    }

    // MARK: - Private

    /// Pauses and resumes, and why, are kept in AutoHush's log (info and
    /// up); the steps between them are only for a live `log stream` (debug).
    private func logActiveSources(after change: String) {
        logger.info("[arbiter] \(change, privacy: .public) (playing now: \(self.playingApps, privacy: .public))")
    }

    /// The apps playing now, for the log: their bundle IDs, or "none".
    var playingApps: String {
        activeSources.isEmpty ? "none" : activeSources.sorted().joined(separator: ", ")
    }

    /// How long an app must play, at most, before the monitor counts it, as
    /// far as known: until it says, the user's start confirmation.
    private var startConfirmation: TimeInterval {
        longestStartConfirmation ?? configuration.sourceStartConfirmation
    }

    /// Resumes a pause taken over at `takenOverAt` once the monitor, starting
    /// afresh, has had `startConfirmation` plus `takeOverMargin` to find an
    /// app still playing.
    private func scheduleTakenOverResume(from takenOverAt: Date) {
        let wait = startConfirmation + Self.takeOverMargin - clock().timeIntervalSince(takenOverAt)
        scheduleResume(after: max(wait, 0))
        takenOver = pendingResumeID.map { (takenOverAt, $0) }
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
