import CoreAudio
import Foundation
import OSLog
import os

/// Watches which apps play audio and tells the arbiter, in order, when one
/// starts or stops.
///
/// Every tick it:
///   1. (on a HAL change, or once per idle interval) re-reads which processes
///      have output running and taps those that are media sources;
///   2. judges each app: by its tapped peak level while levels are measured,
///      otherwise by what it tells macOS (`PlaybackSignals`, AntiDot mode's
///      judge) when it's known to tell, otherwise by its open output stream;
///   3. feeds that into `SourceActivityTracker` and forwards the resulting
///      started/stopped transitions to the arbiter. In AntiDot mode, an app
///      showing no video must play longer before it counts
///      (`AppConfiguration.startConfirmationWithoutVideo`); with open streams
///      only, which can't tell video, every app, for a shorter minimum
///      (`startConfirmationWithOpenStreams`: an app's chat tone keeps its
///      stream open about a second, measured on macOS 14.4). Outside AntiDot
///      mode, while nothing can be measured (Audio Recording denied, or not
///      given yet), apps wait as long, by what judges them: one telling macOS
///      it plays, the longer minimum unless it shows video; one judged by its
///      open stream, the shorter.
///
/// Level detection needs the System Audio Recording permission: without it taps
/// deliver pure silence, which would make every source look stopped. The
/// permission is read from TCC (re-checked every few seconds, and requested at
/// start when undecided). When TCC cannot be queried, level detection is
/// trusted once a tap delivers a non-zero sample (the music player's own output
/// is then tapped too, so its playing proves the permission works).
///
/// Capturing audio makes macOS show its recording indicator, so taps exist only
/// while levels can change a decision (`setAudioLevelsNeeded`, driven by the
/// arbiter: the music playing here or paused by us, with auto-pause on) and the
/// detection method is `.audioLevels`. AntiDot mode's methods capture nothing.
/// Meanwhile an app is judged as in AntiDot mode: one seen telling macOS it
/// plays counts as paused once it stops telling, though its stream stays open
/// (VLC keeps it open about a minute after a pause, measured). Only "Open audio
/// streams only" ignores what apps tell macOS.
///
/// The music player's output also tells whether it plays on THIS Mac. Through
/// Spotify Connect, for example, Spotify reports "playing" while the music
/// comes out of another device; then its process has no running output
/// (measured). The monitor reports this to the arbiter, which only pauses the
/// player when it plays here. The player's output is any process it owns: a
/// Safari web app plays from WebKit's process, which has no name of its own.
///
/// Processes are grouped by the app that owns them (`AudioSourceIdentifying`),
/// so all of Chrome's helpers form one "Google Chrome" source. Sources the user
/// ignores are still tracked and published, but never reach the arbiter.
package final class AudioMonitor: @unchecked Sendable {
    /// What the monitor tells the arbiter, in order.
    enum ArbiterEvent: Sendable {
        /// `heardSince`: for a start, when the app was first heard, if known.
        case source(id: String, isPlaying: Bool, heardSince: Date?)
        case localPlayback(Bool)
        /// How long an app must play, at most, before it counts, as apps
        /// are judged now: told at the first look, then when it changes.
        case startConfirmation(TimeInterval)
        /// An app playing with its microphone on (a call), or no longer.
        case call(id: String, inCall: Bool)
        /// Every event sent before it has reached the arbiter (`eventsDelivered`).
        case delivered(@Sendable () -> Void)
    }

    /// The player playing but its tap silent for this long means level detection
    /// is unavailable. Long enough to outlast the open-but-silent stream a player
    /// keeps for a while after playback moves to another device.
    static let verificationWindow: TimeInterval = 15
    /// How often the System Audio Recording permission is re-read from TCC.
    static let permissionRecheckInterval: TimeInterval = 5
    /// After a HAL change, keep re-reading processes at the active rate for this
    /// long: a process's output flag can flip shortly after the notification.
    static let postChangeRefreshWindow: TimeInterval = 1
    /// A source's process measured silent this long loses its tap, which
    /// keeps macOS's recording indicator on (an app keeping its output open
    /// while paused, as Qobuz does). It's tapped again once its output closes
    /// and opens again, or once it tells macOS it plays anew: one that keeps
    /// saying so in silence (a call app through a quiet stretch) isn't.
    static let silentTapRelease: TimeInterval = 10

    /// Queue-confined; replaced live by `setConfiguration(_:)`.
    var configuration: AppConfiguration
    let snapshotProvider: any AudioProcessSnapshotProviding
    let levelMeter: (any AudioLevelMetering)?
    let permission: (any AudioCapturePermissionChecking)?
    let sourceIdentifier: (any AudioSourceIdentifying)?
    let onAssertionsLearned: @Sendable (String, AnnouncedAssertions) -> Void
    let clock: @Sendable () -> Date
    let onActiveSourcesChange: @Sendable ([AudioSource]) -> Void
    let onDetectionModeChange: @Sendable (DetectionMode) -> Void
    let logger = AutoHushLogger(category: "AudioMonitor")
    let queue = DispatchQueue(label: "AutoHush.AudioMonitor", qos: .userInitiated)
    let events: AsyncStream<ArbiterEvent>.Continuation
    private let forwardingTask: Task<Void, Never>
    /// What the latest tick found, for Diagnostics; read from any thread.
    /// Its entries are worked out only when Diagnostics asks.
    let latestReport = OSAllocatedUnfairLock<ActiveAudioReport?>(initialState: nil)

    // Queue-confined state.
    var isStarted = false
    var timer: DispatchSourceTimer?
    var timerInterval: TimeInterval?
    var candidates: [AudioProcessInfo] = []
    /// The candidates that play the music player's audio: its own processes
    /// and the ones it owns.
    var playerProcesses: Set<AudioObjectID> = []
    /// Owning app of each candidate process.
    var sourceOfProcess: [AudioObjectID: AudioSource] = [:]
    /// IDs of the apps in `sourceOfProcess`.
    var presentSourceIDs: Set<String> = []
    /// Every source seen while it is tracked, so active sources keep their
    /// names during the stop grace period after their process is gone.
    var knownSources: [String: AudioSource] = [:]
    var ignoredSourceIDs: Set<String>
    var needsRefresh = true
    var lastRefresh: Date?
    var lastHALChange: Date?
    var tracker: SourceActivityTracker
    var publishedActive: [AudioSource]?
    var detectionMode: DetectionMode = .pending
    var playerPlayingSince: Date?
    var playerTapSince: Date?
    /// Since when each tapped source process has been measured silent.
    var silentSince: [AudioObjectID: Date] = [:]
    /// Source processes whose tap was released for their silence: they don't
    /// count as playing until they're tapped again (`silentTapRelease`).
    var quietProcesses: Set<AudioObjectID> = []
    /// `nil` while the permission cannot be read (no checker, or TCC unavailable).
    var permissionStatus: AudioCapturePermission?
    var lastPermissionCheck: Date?
    var hasRequestedPermission = false
    /// How playing apps are detected (Settings → Detection → AntiDot mode).
    var detectionMethod: DetectionMethod
    /// AntiDot mode's judge, and what it learned about how apps announce playback.
    var signals: PlaybackSignals
    /// Whether levels can currently change a pause or resume decision.
    var audioLevelsNeeded: Bool
    /// Taps are released this long after levels stop being needed, so brief
    /// gaps (the player's output restarting after a resume) don't recreate them.
    private let audioLevelsReleaseDelay: TimeInterval
    var audioLevelsRelease: DispatchWorkItem?
    var publishedLocalPlayback: Bool?
    var publishedStartConfirmation: TimeInterval?
    /// The apps playing with their microphone on (calls), as last told.
    var callSourceIDs: Set<String> = []
    /// How loud the music was before AutoHush's pause, and the apps
    /// during it (Settings → Advanced).
    var resumeLevel = ResumeLevel()

    package init(
        configuration: AppConfiguration,
        arbiter: any PlaybackArbiting,
        snapshotProvider: any AudioProcessSnapshotProviding = HALAudioProcessSnapshotProvider(),
        levelMeter: (any AudioLevelMetering)? = ProcessTapLevelMeter(),
        audioCapturePermission: (any AudioCapturePermissionChecking)? = nil,
        sourceIdentifier: (any AudioSourceIdentifying)? = nil,
        ignoredSourceIDs: Set<String> = [],
        powerAssertions: (any PowerAssertionReading)? = nil,
        learnedAssertions: [String: AnnouncedAssertions] = [:],
        onAssertionsLearned: @escaping @Sendable (String, AnnouncedAssertions) -> Void = { _, _ in },
        detectionMethod: DetectionMethod = .audioLevels,
        audioLevelsNeeded: Bool = true,
        audioLevelsReleaseDelay: TimeInterval = 2,
        clock: @escaping @Sendable () -> Date = { Date() },
        onActiveSourcesChange: @escaping @Sendable ([AudioSource]) -> Void = { _ in },
        onDetectionModeChange: @escaping @Sendable (DetectionMode) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.snapshotProvider = snapshotProvider
        self.levelMeter = levelMeter
        self.permission = audioCapturePermission
        self.sourceIdentifier = sourceIdentifier
        self.ignoredSourceIDs = ignoredSourceIDs
        self.signals = PlaybackSignals(powerAssertions: powerAssertions, learned: learnedAssertions)
        self.onAssertionsLearned = onAssertionsLearned
        self.detectionMethod = detectionMethod
        self.audioLevelsNeeded = audioLevelsNeeded
        self.audioLevelsReleaseDelay = audioLevelsReleaseDelay
        self.clock = clock
        self.onActiveSourcesChange = onActiveSourcesChange
        self.onDetectionModeChange = onDetectionModeChange
        self.tracker = SourceActivityTracker(configuration: configuration)

        // A single consumer keeps started/stopped events in emission order.
        // The arbiter returns at once (its pauses run on their own), so an
        // event never waits for a fade.
        let (stream, continuation) = AsyncStream.makeStream(of: ArbiterEvent.self)
        self.events = continuation
        self.forwardingTask = Task {
            for await event in stream {
                switch event {
                case .source(let id, let isPlaying, let heardSince):
                    await arbiter.handleSourceChange(sourceID: id, isPlaying: isPlaying, heardSince: heardSince)
                case .localPlayback(let isLocal):
                    await arbiter.handleLocalPlaybackChange(isLocal)
                case .startConfirmation(let longest):
                    await arbiter.handleStartConfirmationChange(longest)
                case .call(let id, let inCall):
                    await arbiter.handleCallChange(sourceID: id, inCall: inCall)
                case .delivered(let done):
                    done()
                }
            }
        }
    }

    deinit {
        events.finish()
        forwardingTask.cancel()
    }

    package func start() {
        queue.async { self.startOnQueue() }
    }

    /// Asynchronous so a pending System Audio Recording prompt (which blocks
    /// tap creation on the monitor queue) can never stall the caller.
    package func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Tells the monitor whether the music player is playing, so it can conclude
    /// that level detection is unavailable when the player's tap stays silent.
    package func setPlayerPlaying(_ isPlaying: Bool) {
        queue.async {
            self.playerPlayingSince = isPlaying ? (self.playerPlayingSince ?? self.clock()) : nil
        }
    }

    /// Applies new timings and thresholds without restarting monitoring.
    package func setConfiguration(_ configuration: AppConfiguration) {
        queue.async {
            self.configuration = configuration
            self.tracker.updateTimings(from: configuration)
        }
    }

    /// Switches the detection method. Only `.audioLevels` captures audio and
    /// checks or requests the System Audio Recording permission.
    package func setDetectionMethod(_ method: DetectionMethod) {
        queue.async {
            guard method != self.detectionMethod else { return }
            self.detectionMethod = method
            self.lastPermissionCheck = nil
            self.signals.forgetAnnouncements()
            if method == .audioLevels {
                if self.detectionMode == .disabled || self.detectionMode == .playbackSignals {
                    self.setDetectionMode(.pending)
                }
            } else {
                self.permissionStatus = nil
            }
            self.needsRefresh = true
            self.tick()
        }
    }

    /// Whether audio levels can currently change a decision. While not
    /// needed, nothing is captured, so macOS shows no recording indicator.
    package func setAudioLevelsNeeded(_ needed: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            self.audioLevelsRelease?.cancel()
            self.audioLevelsRelease = nil
            if needed {
                guard !self.audioLevelsNeeded else { return }
                self.audioLevelsNeeded = true
                self.updateMeteredProcesses(at: self.clock())
            } else if self.audioLevelsNeeded {
                let release = DispatchWorkItem { [weak self] in
                    guard let self, self.audioLevelsRelease != nil else { return }
                    self.audioLevelsRelease = nil
                    self.audioLevelsNeeded = false
                    self.updateMeteredProcesses(at: self.clock())
                }
                self.audioLevelsRelease = release
                self.queue.asyncAfter(deadline: .now() + self.audioLevelsReleaseDelay, execute: release)
            }
        }
    }

    /// Whether the music is paused by AutoHush: its loudness just before
    /// is noted, and the apps' during the pause (with `levelsMusic`).
    package func setMusicPaused(_ paused: Bool) {
        queue.async {
            if !paused, let apps = self.resumeLevel.appsLevel {
                self.logger.info("[level] the apps' loudness during the pause: \(Self.dBFS(apps), privacy: .public) dBFS")
            }
            self.resumeLevel.setMusicPaused(paused, at: self.clock())
            if paused, let reference = self.resumeLevel.reference {
                self.logger.info("[level] the music's loudness at the pause: \(Self.dBFS(reference), privacy: .public) dBFS")
            }
        }
    }

    /// How far (dB, below 0) to lower the Mac's volume as the music
    /// resumes: `nil` unless the apps it was paused for were quieter, or
    /// with `levelsMusic` off or levels unmeasured (AntiDot mode).
    package func resumeOffsetDB() async -> Float? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.configuration.levelsMusic, self.detectionMode == .audioLevel else { return continuation.resume(returning: nil) }
                continuation.resume(returning: self.resumeLevel.offsetDB(maxCut: self.configuration.levelingMaxCutDB,
                                                                         minCut: self.configuration.levelingMinCutDB))
            }
        }
    }

    private static func dBFS(_ rms: Float) -> String {
        String(format: "%.1f", 20 * log10(max(rms, 0.0001)))
    }

    /// Replaces the sources that must never pause the music. Playing sources
    /// that become ignored stop for the arbiter at once, and vice versa. One
    /// no longer ignored starts without saying when it was first heard: it
    /// was playing all along, so nothing that happened meanwhile is its doing.
    package func setIgnoredSources(_ ids: Set<String>) {
        queue.async {
            let previous = self.ignoredSourceIDs
            self.ignoredSourceIDs = ids
            for id in self.tracker.activeSources.sorted() where previous.contains(id) != ids.contains(id) {
                self.events.yield(.source(id: id, isPlaying: previous.contains(id), heardSince: nil))
            }
        }
    }

    /// Returns once every event the monitor has sent so far, and any its
    /// queued work sends, has reached the arbiter. Tests use it to see that
    /// none came.
    package func eventsDelivered() async {
        await withCheckedContinuation { continuation in
            queue.async { self.events.yield(.delivered { continuation.resume() }) }
        }
    }

    /// How each app with its sound on is judged, for Diagnostics (thread-safe).
    package func activeAudioReport() -> [ActiveAudioReport.Entry] {
        latestReport.withLock { $0 }?.entries ?? []
    }
}
