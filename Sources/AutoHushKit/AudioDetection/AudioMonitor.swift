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
///      (`AppConfiguration.startConfirmationWithoutVideo`).
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
    private enum ArbiterEvent: Sendable {
        case source(id: String, isPlaying: Bool)
        case localPlayback(Bool)
    }

    /// The player playing but its tap silent for this long means level detection
    /// is unavailable. Long enough to outlast the open-but-silent stream a player
    /// keeps for a while after playback moves to another device.
    private static let verificationWindow: TimeInterval = 15
    /// How often the System Audio Recording permission is re-read from TCC.
    private static let permissionRecheckInterval: TimeInterval = 5
    /// After a HAL change, keep re-reading processes at the active rate for this
    /// long: a process's output flag can flip shortly after the notification.
    private static let postChangeRefreshWindow: TimeInterval = 1

    /// Queue-confined; replaced live by `setConfiguration(_:)`.
    private var configuration: AppConfiguration
    private let snapshotProvider: any AudioProcessSnapshotProviding
    private let levelMeter: (any AudioLevelMetering)?
    private let permission: (any AudioCapturePermissionChecking)?
    private let sourceIdentifier: (any AudioSourceIdentifying)?
    private let onAssertionsLearned: @Sendable (String, AnnouncedAssertions) -> Void
    private let clock: @Sendable () -> Date
    private let onActiveSourcesChange: @Sendable ([AudioSource]) -> Void
    private let onDetectionModeChange: @Sendable (DetectionMode) -> Void
    private let logger = Logger(category: "AudioMonitor")
    private let queue = DispatchQueue(label: "AutoHush.AudioMonitor", qos: .userInitiated)
    private let events: AsyncStream<ArbiterEvent>.Continuation
    private let forwardingTask: Task<Void, Never>
    /// What the latest tick found, for Diagnostics; read from any thread.
    /// Its entries are worked out only when Diagnostics asks.
    private let latestReport = OSAllocatedUnfairLock<ActiveAudioReport?>(initialState: nil)

    // Queue-confined state.
    private var isStarted = false
    private var timer: DispatchSourceTimer?
    private var timerInterval: TimeInterval?
    private var candidates: [AudioProcessInfo] = []
    /// The candidates that play the music player's audio: its own processes
    /// and the ones it owns.
    private var playerProcesses: Set<AudioObjectID> = []
    /// Owning app of each candidate process.
    private var sourceOfProcess: [AudioObjectID: AudioSource] = [:]
    /// IDs of the apps in `sourceOfProcess`.
    private var presentSourceIDs: Set<String> = []
    /// Every source seen while it is tracked, so active sources keep their
    /// names during the stop grace period after their process is gone.
    private var knownSources: [String: AudioSource] = [:]
    private var ignoredSourceIDs: Set<String>
    private var needsRefresh = true
    private var lastRefresh: Date?
    private var lastHALChange: Date?
    private var tracker: SourceActivityTracker
    private var publishedActive: [AudioSource]?
    private var detectionMode: DetectionMode = .pending
    private var playerPlayingSince: Date?
    private var playerTapSince: Date?
    /// `nil` while the permission cannot be read (no checker, or TCC unavailable).
    private var permissionStatus: AudioCapturePermission?
    private var lastPermissionCheck: Date?
    private var hasRequestedPermission = false
    /// How playing apps are detected (Settings → Detection → AntiDot mode).
    private var detectionMethod: DetectionMethod
    /// AntiDot mode's judge, and what it learned about how apps announce playback.
    private var signals: PlaybackSignals
    /// Whether levels can currently change a pause or resume decision.
    private var audioLevelsNeeded: Bool
    /// Taps are released this long after levels stop being needed, so brief
    /// gaps (the player's output restarting after a resume) don't recreate them.
    private let audioLevelsReleaseDelay: TimeInterval
    private var audioLevelsRelease: DispatchWorkItem?
    private var publishedLocalPlayback: Bool?

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
                case .source(let id, let isPlaying):
                    await arbiter.handleSourceChange(sourceID: id, isPlaying: isPlaying)
                case .localPlayback(let isLocal):
                    await arbiter.handleLocalPlaybackChange(isLocal)
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

    /// Replaces the sources that must never pause the music. Playing sources
    /// that become ignored stop for the arbiter at once, and vice versa.
    package func setIgnoredSources(_ ids: Set<String>) {
        queue.async {
            let previous = self.ignoredSourceIDs
            self.ignoredSourceIDs = ids
            for id in self.tracker.activeSources.sorted() where previous.contains(id) != ids.contains(id) {
                self.events.yield(.source(id: id, isPlaying: previous.contains(id)))
            }
        }
    }

    /// How each app with its sound on is judged, for Diagnostics (thread-safe).
    package func activeAudioReport() -> [ActiveAudioReport.Entry] {
        latestReport.withLock { $0 }?.entries ?? []
    }

    // MARK: - Lifecycle

    private func startOnQueue() {
        guard !isStarted else { return }
        isStarted = true

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer

        snapshotProvider.startObserving(on: queue) { [weak self] in
            guard let self else { return }
            self.needsRefresh = true
            self.lastHALChange = self.clock()
            self.tick()
        }
        needsRefresh = true
        tick()
    }

    private func stopOnQueue() {
        guard isStarted else { return }
        isStarted = false

        timer?.cancel()
        timer = nil
        timerInterval = nil
        audioLevelsRelease?.cancel()
        audioLevelsRelease = nil
        snapshotProvider.stopObserving()
        levelMeter?.stopAll()

        candidates = []
        playerProcesses = []
        sourceOfProcess = [:]
        presentSourceIDs = []
        knownSources = [:]
        tracker.reset()
        signals.forgetAnnouncements()
        lastRefresh = nil
        lastHALChange = nil
        playerTapSince = nil
        lastPermissionCheck = nil
        publishedLocalPlayback = nil
        publishActiveSources()
        latestReport.withLock { $0 = nil }
    }

    // MARK: - Tick

    private func tick() {
        guard isStarted else { return }
        let now = clock()
        checkPermission(at: now)
        if needsRefresh || recentlyChanged(at: now)
            || lastRefresh.map({ now.timeIntervalSince($0) >= configuration.idleSampleInterval }) ?? true {
            refreshCandidates(at: now)
        }
        evaluate(at: now)
        rescheduleTimer(at: now)
    }

    private func recentlyChanged(at now: Date) -> Bool {
        lastHALChange.map { now.timeIntervalSince($0) < Self.postChangeRefreshWindow } ?? false
    }

    private func refreshCandidates(at now: Date) {
        needsRefresh = false
        lastRefresh = now
        let ownPID = getpid()
        candidates = snapshotProvider.activeProcesses().filter { $0.pid != ownPID }
        playerProcesses = Set(candidates.filter { configuration.isMusicPlayer($0.bundleID) }.map(\.objectID))
        sourceOfProcess = [:]
        // A process without a bundle ID (a command-line player such as afplay
        // or mpv) counts as the app that owns it, e.g. Terminal; one no app
        // owns (a system daemon) is left with an empty ID and doesn't count.
        for process in candidates where process.bundleID.isEmpty || configuration.isMediaSource(process.bundleID) {
            let source = sourceIdentifier?.source(for: process)
                ?? AudioSource(id: process.bundleID, name: process.bundleID)
            if configuration.isMusicPlayer(source.id) { playerProcesses.insert(process.objectID) }
            // An excluded owner (e.g. the music player's helper) excludes its processes too.
            guard configuration.isMediaSource(source.id) else { continue }
            sourceOfProcess[process.objectID] = source
            knownSources[source.id] = source
        }
        presentSourceIDs = Set(sourceOfProcess.values.map(\.id))
        updateMeteredProcesses(at: now)
    }

    /// Re-reads the System Audio Recording permission (at most every few
    /// seconds) and derives the detection mode from it when it is known.
    private func checkPermission(at now: Date) {
        guard detectionMethod == .audioLevels else {
            setDetectionMode(detectionMethod == .playbackSignals ? .playbackSignals : .disabled)
            return
        }
        guard let permission else { return }
        if let lastPermissionCheck,
           now.timeIntervalSince(lastPermissionCheck) < Self.permissionRecheckInterval { return }
        lastPermissionCheck = now

        let status = permission.status()
        let changed = status != permissionStatus
        permissionStatus = status
        switch status {
        case .granted:
            setDetectionMode(.audioLevel)
        case .denied:
            setDetectionMode(.unavailable)
        case .notDetermined:
            setDetectionMode(.pending)
            requestPermissionOnce(permission)
        case nil:
            break
        }
        if changed {
            logger.info("[monitor] System Audio Recording permission: \(status.map { "\($0)" } ?? "unknown", privacy: .public)")
            updateMeteredProcesses(at: now)
        }
    }

    private func requestPermissionOnce(_ permission: any AudioCapturePermissionChecking) {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        permission.request { [weak self] _ in
            guard let monitor = self else { return }
            monitor.queue.async {
                monitor.lastPermissionCheck = nil // re-read right away
                monitor.tick()
            }
        }
    }

    /// Taps are created only when they matter (see the type comment) and can
    /// deliver samples: with the permission granted, or when it cannot be
    /// read (then samples decide).
    private var shouldMeterLevels: Bool {
        detectionMethod == .audioLevels && audioLevelsNeeded
            && (permissionStatus == nil || permissionStatus == .granted)
    }

    private func updateMeteredProcesses(at now: Date) {
        guard let levelMeter else { return }
        // The player is tapped only to prove the permission when TCC cannot be read.
        let verifiesWithPlayer = permissionStatus == nil && detectionMode != .audioLevel
        let metered = shouldMeterLevels ? candidates.filter {
            sourceOfProcess[$0.objectID] != nil || (verifiesWithPlayer && playerProcesses.contains($0.objectID))
        } : []
        let tapsPlayer = metered.contains { playerProcesses.contains($0.objectID) }
        playerTapSince = tapsPlayer ? (playerTapSince ?? now) : nil
        // May block while macOS shows the System Audio Recording prompt.
        levelMeter.setMeteredProcesses(Set(metered.map(\.objectID)))
    }

    private func evaluate(at now: Date) {
        let peaks = levelMeter?.drainPeaks() ?? [:]
        updateDetectionMode(peaks: peaks, at: now)

        var audible: Set<String> = []
        var levels: [String: Float] = [:]
        let judgement = judgePlaybackSignals(at: now)
        /// The verdicts that decided: only for what wasn't measured.
        var verdicts: [String: Bool] = [:]
        for process in candidates {
            guard let source = sourceOfProcess[process.objectID] else { continue }
            let peak = detectionMode == .audioLevel ? peaks[process.objectID] : nil
            if let peak { levels[source.id] = max(levels[source.id] ?? 0, peak) }
            let verdict = peak == nil ? judgement?.verdicts[source.id] : nil
            if let verdict { verdicts[source.id] = verdict }
            if isAudible(peak: peak, verdict: verdict) {
                audible.insert(source.id)
            }
        }

        // Before source events, so a pause decision in this tick sees it.
        updateLocalPlayback()

        // AntiDot mode: sound without video must last longer (see the type comment).
        let slowStarts = detectionMethod != .playbackSignals ? [:] : judgement.map { judgement in
            Dictionary(uniqueKeysWithValues: audible.subtracting(judgement.showingVideo).map {
                ($0, configuration.startConfirmationWithoutVideo)
            })
        } ?? [:]
        let (started, stopped) = tracker.update(audible: audible, at: now, startConfirmations: slowStarts)
        if !started.isEmpty || !stopped.isEmpty {
            logger.debug("[monitor] +[\(started.sorted().joined(separator: ","), privacy: .public)] -[\(stopped.sorted().joined(separator: ","), privacy: .public)]")
        }
        for id in started.sorted() where !ignoredSourceIDs.contains(id) {
            events.yield(.source(id: id, isPlaying: true))
        }
        for id in stopped.sorted() where !ignoredSourceIDs.contains(id) {
            events.yield(.source(id: id, isPlaying: false))
        }

        // Forget sources that are neither tracked nor currently present.
        knownSources = knownSources.filter { tracker.isTracking($0.key) || presentSourceIDs.contains($0.key) }

        publishActiveSources()
        publishReport(audible: audible, levels: levels, verdicts: verdicts)
    }

    /// Whether one process of a source counts as audible in this tick: by its
    /// level when measured, else by what its app tells macOS, else by its open
    /// output stream.
    private func isAudible(peak: Float?, verdict: Bool?) -> Bool {
        if let peak { return peak >= configuration.audibleThreshold }
        if let verdict { return verdict }
        return true
    }

    /// What the apps with their sound on tell macOS, as AntiDot mode judges
    /// it; not with "Open audio streams only". Saves what it learned.
    private func judgePlaybackSignals(at now: Date) -> PlaybackSignals.Judgement? {
        guard detectionMethod != .openStreams else { return nil }
        var appOfProcess: [pid_t: String] = [:]
        for process in candidates {
            if let source = sourceOfProcess[process.objectID] { appOfProcess[process.pid] = source.id }
        }
        let holding = signals.assertions(among: presentSourceIDs) { pid in
            appOfProcess[pid] ?? sourceIdentifier?.sourceID(forPID: pid)
        }
        let judgement = signals.judge(present: presentSourceIDs, holding: holding, at: now)
        for (id, assertions) in judgement.learned.sorted(by: { $0.key < $1.key }) {
            // Names are the app's own words, so they stay private in the log.
            logger.info("[monitor] \(id, privacy: .public) keeps awake while playing: system \(assertions.system.sorted()), display \(assertions.display.sorted())")
            onAssertionsLearned(id, assertions)
        }
        return judgement
    }

    /// Infers the permission from samples; only used when TCC cannot be read.
    private func updateDetectionMode(peaks: [AudioObjectID: Float], at now: Date) {
        guard permissionStatus == nil else { return }
        if detectionMode != .audioLevel, peaks.values.contains(where: { $0 > 0 }) {
            setDetectionMode(.audioLevel)
            updateMeteredProcesses(at: now) // verification taps on the player are no longer needed
        } else if detectionMode == .pending,
                  let playingSince = playerPlayingSince,
                  let tapSince = playerTapSince,
                  now.timeIntervalSince(max(playingSince, tapSince)) >= Self.verificationWindow {
            setDetectionMode(.unavailable)
        }
    }

    /// The player plays on this Mac when a process of its own has output
    /// running. Its output is not tapped: that would keep the recording
    /// indicator on for as long as the music plays.
    private func updateLocalPlayback() {
        let isLocal = !playerProcesses.isEmpty
        guard isLocal != publishedLocalPlayback else { return }
        publishedLocalPlayback = isLocal
        logger.debug("[monitor] music player output on this Mac: \(isLocal, privacy: .public)")
        events.yield(.localPlayback(isLocal))
    }

    private func setDetectionMode(_ mode: DetectionMode) {
        guard mode != detectionMode else { return }
        detectionMode = mode
        logger.info("[monitor] detection: \(String(describing: mode), privacy: .public)")
        onDetectionModeChange(mode)
    }

    private func rescheduleTimer(at now: Date) {
        let interval = Self.tickInterval(
            otherAppsRunning: !sourceOfProcess.isEmpty,
            isTracking: !tracker.isIdle,
            recentlyChanged: recentlyChanged(at: now),
            configuration: configuration
        )
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 100))
        )
    }

    /// The active rate while another app has its audio running, a source is
    /// tracked, or the process list just changed; otherwise the idle rate.
    /// The music player playing alone leaves nothing to judge, and a new app
    /// starting is announced by a HAL change, which ticks at once.
    static func tickInterval(
        otherAppsRunning: Bool, isTracking: Bool, recentlyChanged: Bool, configuration: AppConfiguration
    ) -> TimeInterval {
        otherAppsRunning || isTracking || recentlyChanged
            ? configuration.activeSampleInterval
            : configuration.idleSampleInterval
    }

    // MARK: - Publication

    private func publishActiveSources() {
        let active = tracker.activeSources
            .map { knownSources[$0] ?? AudioSource(id: $0, name: $0) }
            .sortedByName()
        guard active != publishedActive else { return }
        publishedActive = active
        onActiveSourcesChange(active)
    }

    private func publishReport(audible: Set<String>, levels: [String: Float], verdicts: [String: Bool]) {
        let report = ActiveAudioReport(
            present: presentSourceIDs,
            playing: tracker.activeSources,
            audible: audible,
            levels: levels,
            ignored: ignoredSourceIDs,
            announcing: Set(verdicts.filter { $0.value }.keys),
            notAnnouncing: Set(verdicts.filter { !$0.value }.keys),
            sources: knownSources
        )
        latestReport.withLock { $0 = report }
    }
}
