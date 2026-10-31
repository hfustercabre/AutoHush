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
/// another device (a player's own remote playback) does not compete with local
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
    let debounceScheduler: any PlaybackArbiterDebounceScheduling
    /// What the app is told: the playback state, why a pause or resume
    /// failed, and whether the player is muted in place of the pause.
    let onStatusUpdate: @Sendable (MonitoringStatusUpdate) -> Void
    let onAudioLevelsNeededChange: @Sendable (Bool) -> Void
    /// Whether the music is paused by us now, for its loudness and the
    /// apps' (`AudioMonitor.setMusicPaused`).
    let onPausedByUsChange: @Sendable (Bool) -> Void
    /// Lowers the Mac's volume as the music resumes after quieter apps, by
    /// `resumeOffset` (Settings → Behavior, `levelsMusic`).
    let volumeLeveler: any ResumeLeveling?
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
    /// The last pause failed, while other apps play: the music plays on.
    /// Over once they stop, a pause works, or the player stops playing.
    var pauseFailure: MusicPlayerError? {
        didSet { if pauseFailure != oldValue { onStatusUpdate(.pauseFailure(pauseFailure)) } }
    }
    /// The last resume got no answer from the player, or its play failed,
    /// after its tries: the menu says so with Try Again (`retryResume`; the
    /// user, 2026-10-25). Over once an app starts, the player says how it
    /// is, or Try Again.
    var resumeFailure: MusicPlayerError? {
        didSet { if resumeFailure != oldValue { onStatusUpdate(.resumeFailure(resumeFailure)) } }
    }
    var publishedAudioLevelsNeeded: Bool?
    let logger = AutoHushLogger(category: "PlaybackArbiter")

    var pausedByUs = false
    /// The pause held is a mute (`muteIfPlayingAnyway`), lifted by `shutdown`.
    var heldByMute = false
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
    /// How many states the player's observer reported (`handlePlayerStateChange`).
    private(set) var playerReports = 0
    /// Assumed true until AudioMonitor reports, which it does on its first tick.
    var playsLocally = true
    /// It says it plays here, but wasn't heard when last asked
    /// (`hearsPlayer`): playing silently, not paused.
    var playsSilently = false
    /// Not heard, and only its open output said it plays (it reports no
    /// state, as a player's autoplaying trailers may): shown as not playing.
    var silentWithoutState = false
    /// Whether the player is heard, from the levels the monitor measures
    /// alongside other apps (`AudioMonitor.playerHearing`), counting only its
    /// sound after `since` when given. Never with a tap of its own: the menu
    /// opening listened so until the user dropped it (K5, 2026-10-26: macOS
    /// showed the purple dot each time).
    let hearsPlayer: @Sendable (_ since: Date?) async -> PlayerHearing
    /// Listens once to the apps that went quiet with their sound kept open
    /// (`AudioMonitor.listenToQuietApps`): whether one plays again. Asked
    /// just before a resume (R2, the user, 2026-10-27).
    let quietAppPlaysAgain: @Sendable () async -> Bool
    /// When AutoHush's pause, or its mute in place of one, took
    /// (`handleRestart`).
    var pausedAt: Date?
    /// What the player's sound said when last asked during AutoHush's pause
    /// (`watchRestart`): `nil` until then, or with nothing measured.
    var hearingDuringPause: PlayerHearing?
    /// The user played the player while other apps play (or AutoHush let
    /// them have it): left alone until another app starts, or none plays.
    var leftToUser = false
    /// Since when other apps play, without a gap: input to the player since
    /// then makes a start the user's (`playerStartedDuringApps`).
    var appsPlayingSince: Date?
    /// Since when the player has been heard while it says it doesn't play
    /// (`mutesHeardWhileQuiet`): still heard past a pause's tail, it's muted.
    var heardWhileQuietSince: Date?
    /// The pending look at whether the player is heard again (`watchRestart`),
    /// with its wait, and the looks called off whose tasks haven't ended
    /// (`waitUntilIdle`).
    var restartWatch: (task: Task<Void, Never>, wait: Task<Void, Never>)?
    var calledOffWatches: [UUID: (task: Task<Void, Never>, wait: Task<Void, Never>)] = [:]
    /// The look under way, once its wait is over (`waitUntilIdle`).
    var lookUnderWay: Task<Void, Never>?
    /// AutoHush's mute of the player during its pause (`PlayerMuting`),
    /// lifted in one place (`endPauseMute`); the app is told whether it's
    /// muted in place of the pause.
    var mute = MuteState() {
        didSet { if mutedInstead != oldValue.isInsteadOfPause { onStatusUpdate(.mutedInstead(mutedInstead)) } }
    }
    /// Muted in place of the pause: it plays on, silent (`PauseMute.insteadOfPause`).
    var mutedInstead: Bool { mute.isInsteadOfPause }
    /// The lifting of the last mute, under way (`publishPlaybackState`).
    var muteLift: Task<Void, Never>?
    /// Whether the user pressed a key or clicked in the player, while it was
    /// already in front, after a moment (`PlayerInput`; media keys don't
    /// count); by default always, so every start is the user's (the
    /// monitoring gives the real one).
    let inputToPlayer: @Sendable (Date) -> Bool
    let playerMute: (any PlayerMuting)?
    /// Whether the player may be muted through a tap now: not in AntiDot
    /// mode. Read live, so a mute whose tap was being made as it turned on
    /// is lifted too (`muteInsteadOfPause`).
    let tapsAllowed: @Sendable () -> Bool
    var autoPauseEnabled: Bool
    var activeSources: Set<String> = []
    /// The apps playing with their microphone on (calls).
    var callSources: Set<String> = []
    /// The output went away while a pause was fading out: once it's held,
    /// it's forgotten (`handleOutputDisconnected`).
    var outputGoneDuringPause = false
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
    /// How often a player playing silently, or paused or muted by AutoHush,
    /// is looked at again while other apps play. The monitor tells the moment
    /// it's heard again (`handlePlayerHeard`): this is the rest.
    static let silentRecheckInterval: TimeInterval = 1
    /// The player's sound up to this long after AutoHush's pause may be its
    /// sound from before it, still in the measure (a tick's lag, a buffer).
    static let pauseTail: TimeInterval = 0.4
    /// The first look at whether the pause took comes this long after it:
    /// past `pauseTail`, and a tick of the monitor's.
    static let restartWatchDelay: TimeInterval = 0.75
    /// Muted in place of the pause and still heard, its pause is pressed
    /// again this often (`lookWhileMuted`).
    static let mutedPauseRetry: TimeInterval = 2
    /// How long a failed press of its pause waits for the next, muted:
    /// `mutedPauseRetry`, doubled with each failure in a row, at most a
    /// minute (2026-10-27: a player whose way kept failing was pressed every
    /// second, the menu bar's Now Playing opened each time).
    static func mutedPauseWait(afterFailures failures: Int) -> TimeInterval {
        Backoff.doubling(afterFailures: failures, within: mutedPauseRetry...60)
    }
    /// The user's input counts as their play only when the player is heard
    /// again within this long of it (`userPlayedJustNow`).
    static let playInputWindow: TimeInterval = 3
    /// How long after a resume a polled player is asked again (`confirmResumeLater`).
    static let resumeConfirmDelay: TimeInterval = 3
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
    /// An app that pauses other players does it as it starts (one did 0.3 s
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
        debounceScheduler: any PlaybackArbiterDebounceScheduling = TaskSleepDebounceScheduler(),
        fadeSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
        clock: @escaping @Sendable () -> Date = { Date() },
        autoPauseEnabled: Bool = true,
        resumesHeld: Bool = false,
        onStatusUpdate: @escaping @Sendable (MonitoringStatusUpdate) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in },
        onPausedByUsChange: @escaping @Sendable (Bool) -> Void = { _ in },
        volumeLeveler: any ResumeLeveling? = nil,
        resumeOffset: @escaping @Sendable () async -> Float? = { nil },
        hearsPlayer: @escaping @Sendable (_ since: Date?) async -> PlayerHearing = { _ in .unknown },
        quietAppPlaysAgain: @escaping @Sendable () async -> Bool = { false },
        inputToPlayer: @escaping @Sendable (Date) -> Bool = { _ in true },
        playerMute: (any PlayerMuting)? = nil,
        tapsAllowed: @escaping @Sendable () -> Bool = { true }
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
        self.onStatusUpdate = onStatusUpdate
        self.onAudioLevelsNeededChange = onAudioLevelsNeededChange
        self.onPausedByUsChange = onPausedByUsChange
        self.volumeLeveler = volumeLeveler
        self.resumeOffset = resumeOffset
        self.hearsPlayer = hearsPlayer
        self.quietAppPlaysAgain = quietAppPlaysAgain
        self.inputToPlayer = inputToPlayer
        self.playerMute = playerMute
        self.tapsAllowed = tapsAllowed
    }

    /// Stops all future actions, including an already scheduled resume.
    /// Called as its monitoring stops: a new start replaces it, or AutoHush quits.
    func shutdown() async {
        isShutDown = true
        cancelPendingPause()
        cancelPendingResume()
        await fader.abandon() // never leave the music faded down
        restartWatch?.task.cancel()
        restartWatch = nil
        await liftPauseMute()
        // Nor muted: a mute, unlike a pause, can't be undone by the user.
        if heldByMute, let muting = player as? any MutingMusicPlayer { await muting.releaseMute() }
        heldByMute = false
        // Nor the Mac's volume lowered, unless another monitoring lowered it.
        if let levelLowered { volumeLeveler?.restoreNow(lowered: levelLowered) }
        levelLowered = nil
        resumeLowered = false
    }

    /// Notes `change` as the latest sleep or wake applied (`setAsleep`);
    /// false for one no newer than that, which comes late and is ignored.
    func noteSleepChange(_ change: Int) -> Bool {
        guard change > sleepChange else { return false }
        sleepChange = change
        return true
    }

    /// Counts a state the player's observer reported (`playerReports`).
    func notePlayerReport() {
        playerReports += 1
    }
}
