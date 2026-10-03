import CoreAudio
import Foundation
import OSLog
import os

// MARK: - Audio monitor
//
// Every tick:
//   1. (on HAL change, or once per idle interval) re-reads which processes have
//      output running and taps those that are media sources;
//   2. classifies each source as audible — by tapped peak level when level
//      detection works, otherwise by its open output stream;
//   3. feeds that into SourceActivityTracker and forwards the resulting
//      started/stopped transitions, in order, to the arbiter.
//
// Level detection needs the System Audio Recording permission: without it taps
// deliver pure silence, which would make every source look stopped. The
// permission is read from TCC (re-checked every few seconds, and requested at
// start when undecided). When TCC cannot be queried, level detection is
// trusted once a tap delivers a non-zero sample (the music player's own output
// is then tapped too, so its playing proves the permission works).
//
// Capturing audio makes macOS show its recording indicator, so taps exist only
// while levels can change a decision (`setAudioLevelsNeeded`, driven by the
// arbiter: the music playing here or paused by us, with auto-pause on) and the
// detection method is `.audioLevels`. With `.playbackSignals` (AntiDot mode)
// nothing is captured and no app is singled out: every app is judged by its
// power assertions (PowerAssertionReading). An app announcing "don't sleep"
// counts as playing; one seen announcing before but not now counts as paused,
// even with its audio open. Apps that never announce count as playing while
// their output is open, as with `.openStreams`.
//
// The music player's output also tells whether it plays on THIS Mac. Through
// Spotify Connect, for example, Spotify reports "playing" while the music
// comes out of another device; then its process has no running output
// (measured). The monitor reports this to the arbiter, which only pauses the
// player when it plays here.
//
// Processes are grouped by the app that owns them (AudioSourceIdentifying), so
// all of Chrome's helpers form one "Google Chrome" source. Sources the user
// ignores are still tracked and published, but never reach the arbiter.

final class AudioMonitor: @unchecked Sendable {
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
    private let powerAssertions: (any PowerAssertionReading)?
    private let onAnnouncingSourceLearned: @Sendable (String) -> Void
    private let clock: @Sendable () -> Date
    private let onActiveSourcesChange: @Sendable ([AudioSource]) -> Void
    private let onDetectionModeChange: @Sendable (DetectionMode) -> Void
    private let logger = Logger(category: "AudioMonitor")
    private let queue = DispatchQueue(label: "AutoHush.AudioMonitor", qos: .userInitiated)
    private let events: AsyncStream<ArbiterEvent>.Continuation
    private let forwardingTask: Task<Void, Never>
    private let report = OSAllocatedUnfairLock<(active: [AudioSource], lines: [String])>(initialState: ([], []))

    // Queue-confined state.
    private var isStarted = false
    private var timer: DispatchSourceTimer?
    private var timerInterval: TimeInterval?
    private var candidates: [AudioProcessInfo] = []
    /// Owning app of each candidate process.
    private var sourceOfProcess: [AudioObjectID: AudioSource] = [:]
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
    /// How playing apps are detected (Settings → General → AntiDot mode).
    private var detectionMethod: DetectionMethod
    /// Apps seen announcing playback through a power assertion.
    private var announcingSourceIDs: Set<String>
    /// Whether levels can currently change a pause or resume decision.
    private var audioLevelsNeeded: Bool
    /// Taps are released this long after levels stop being needed, so brief
    /// gaps (the player's output restarting after a resume) don't recreate them.
    private let audioLevelsReleaseDelay: TimeInterval
    private var audioLevelsRelease: DispatchWorkItem?
    private var publishedLocalPlayback: Bool?

    init(
        configuration: AppConfiguration,
        arbiter: any PlaybackArbiting,
        snapshotProvider: any AudioProcessSnapshotProviding = HALAudioProcessSnapshotProvider(),
        levelMeter: (any AudioLevelMetering)? = ProcessTapLevelMeter(),
        audioCapturePermission: (any AudioCapturePermissionChecking)? = nil,
        sourceIdentifier: (any AudioSourceIdentifying)? = nil,
        ignoredSourceIDs: Set<String> = [],
        powerAssertions: (any PowerAssertionReading)? = nil,
        announcingSourceIDs: Set<String> = [],
        onAnnouncingSourceLearned: @escaping @Sendable (String) -> Void = { _ in },
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
        self.powerAssertions = powerAssertions
        self.announcingSourceIDs = announcingSourceIDs
        self.onAnnouncingSourceLearned = onAnnouncingSourceLearned
        self.detectionMethod = detectionMethod
        self.audioLevelsNeeded = audioLevelsNeeded
        self.audioLevelsReleaseDelay = audioLevelsReleaseDelay
        self.clock = clock
        self.onActiveSourcesChange = onActiveSourcesChange
        self.onDetectionModeChange = onDetectionModeChange
        self.tracker = SourceActivityTracker(configuration: configuration)

        // A single consumer keeps started/stopped events in emission order.
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

    func start() {
        queue.async { self.startOnQueue() }
    }

    /// Asynchronous so a pending System Audio Recording prompt (which blocks
    /// tap creation on the monitor queue) can never stall the caller.
    func stop() {
        queue.async { self.stopOnQueue() }
    }

    /// Tells the monitor whether the music player is playing, so it can conclude
    /// that level detection is unavailable when the player's tap stays silent.
    func setPlayerPlaying(_ isPlaying: Bool) {
        queue.async {
            self.playerPlayingSince = isPlaying ? (self.playerPlayingSince ?? self.clock()) : nil
        }
    }

    /// Applies new timings and thresholds without restarting monitoring.
    func setConfiguration(_ configuration: AppConfiguration) {
        queue.async {
            self.configuration = configuration
            self.tracker.updateTimings(from: configuration)
        }
    }

    /// Switches the detection method. Only `.audioLevels` captures audio and
    /// checks or requests the System Audio Recording permission.
    func setDetectionMethod(_ method: DetectionMethod) {
        queue.async {
            guard method != self.detectionMethod else { return }
            self.detectionMethod = method
            self.lastPermissionCheck = nil
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
    func setAudioLevelsNeeded(_ needed: Bool) {
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
    func setIgnoredSources(_ ids: Set<String>) {
        queue.async {
            let previous = self.ignoredSourceIDs
            self.ignoredSourceIDs = ids
            for id in self.tracker.activeSources.sorted() where previous.contains(id) != ids.contains(id) {
                self.events.yield(.source(id: id, isPlaying: previous.contains(id)))
            }
        }
    }

    /// Foreign sources currently considered playing, including ignored ones (thread-safe).
    func currentActiveSources() -> [AudioSource] {
        report.withLock { $0.active }
    }

    /// Human-readable per-source state for the Diagnostics alert (thread-safe).
    func activeAudioReport() -> [String] {
        report.withLock { $0.lines }
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
        sourceOfProcess = [:]
        knownSources = [:]
        tracker.reset()
        lastRefresh = nil
        lastHALChange = nil
        playerTapSince = nil
        lastPermissionCheck = nil
        publishedLocalPlayback = nil
        publishActiveSources()
        report.withLock { $0.lines = [] }
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
        candidates = snapshotProvider.activeProcesses().filter {
            $0.isRunningOutput && $0.pid != ownPID && !$0.bundleID.isEmpty
        }
        sourceOfProcess = [:]
        for process in candidates where configuration.isMediaSource(process.bundleID) {
            let source = sourceIdentifier?.source(for: process)
                ?? AudioSource(id: process.bundleID, name: process.bundleID)
            // An excluded owner (e.g. the music player's helper) excludes its processes too.
            guard configuration.isMediaSource(source.id) else { continue }
            sourceOfProcess[process.objectID] = source
            knownSources[source.id] = source
        }
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
            sourceOfProcess[$0.objectID] != nil
                || (verifiesWithPlayer && configuration.musicPlayerBundleIDs.contains($0.bundleID))
        } : []
        let tapsPlayer = metered.contains { configuration.musicPlayerBundleIDs.contains($0.bundleID) }
        playerTapSince = tapsPlayer ? (playerTapSince ?? now) : nil
        // May block while macOS shows the System Audio Recording prompt.
        levelMeter.setMeteredProcesses(Set(metered.map(\.objectID)))
    }

    private func evaluate(at now: Date) {
        let peaks = levelMeter?.drainPeaks() ?? [:]
        updateDetectionMode(peaks: peaks, at: now)

        var audible: Set<String> = []
        var levels: [String: Float] = [:]
        let awake = sourcesKeepingSystemAwake()
        for process in candidates {
            guard let source = sourceOfProcess[process.objectID] else { continue }
            let peak = detectionMode == .audioLevel ? peaks[process.objectID] : nil
            if let peak { levels[source.id] = max(levels[source.id] ?? 0, peak) }
            if isAudible(source.id, peak: peak, keepsSystemAwake: awake.contains(source.id)) {
                audible.insert(source.id)
            }
        }

        // Before source events, so a pause decision in this tick sees it.
        updateLocalPlayback()

        let (started, stopped) = tracker.update(audible: audible, at: now)
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
        let present = Set(sourceOfProcess.values.map(\.id))
        knownSources = knownSources.filter { tracker.isTracking($0.key) || present.contains($0.key) }

        publishActiveSources()
        publishReport(audible: audible, levels: levels, awake: awake)
    }

    /// Whether one process of a source counts as audible in this tick.
    private func isAudible(_ sourceID: String, peak: Float?, keepsSystemAwake: Bool) -> Bool {
        if detectionMethod == .playbackSignals {
            if keepsSystemAwake {
                learnAnnouncing(sourceID)
                return true
            }
            // Announced playback before but not now: paused with its audio open.
            if announcingSourceIDs.contains(sourceID) { return false }
        }
        if let peak { return peak >= configuration.audibleThreshold }
        return true // judged by its open output stream
    }

    /// Owning apps of processes that hold a system-sleep assertion, with
    /// AntiDot mode's `.playbackSignals` method only.
    private func sourcesKeepingSystemAwake() -> Set<String> {
        guard detectionMethod == .playbackSignals, let powerAssertions, !sourceOfProcess.isEmpty else { return [] }
        let holders = powerAssertions.pidsKeepingSystemAwake()
        guard !holders.isEmpty else { return [] }
        var sourceByPID: [pid_t: String] = [:]
        for process in candidates {
            if let source = sourceOfProcess[process.objectID] { sourceByPID[process.pid] = source.id }
        }
        let present = Set(sourceOfProcess.values.map(\.id))
        return Set(holders.compactMap { sourceByPID[$0] ?? sourceIdentifier?.sourceID(forPID: $0) })
            .intersection(present)
    }

    private func learnAnnouncing(_ id: String) {
        guard announcingSourceIDs.insert(id).inserted else { return }
        logger.info("[monitor] \(id, privacy: .public) announces playback with a power assertion")
        onAnnouncingSourceLearned(id)
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

    /// The player plays on this Mac when its process has output running. Its
    /// output is not tapped: that would keep the recording indicator on for
    /// as long as the music plays.
    private func updateLocalPlayback() {
        let isLocal = candidates.contains { configuration.musicPlayerBundleIDs.contains($0.bundleID) }
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
        let interval = candidates.isEmpty && tracker.isIdle && !recentlyChanged(at: now)
            ? configuration.idleSampleInterval
            : configuration.activeSampleInterval
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(Int(interval * 100))
        )
    }

    // MARK: - Publication

    private func publishActiveSources() {
        let active = tracker.activeSources
            .map { knownSources[$0] ?? AudioSource(id: $0, name: $0) }
            .sortedByName()
        report.withLock { $0.active = active }
        guard active != publishedActive else { return }
        publishedActive = active
        onActiveSourcesChange(active)
    }

    private func publishReport(audible: Set<String>, levels: [String: Float], awake: Set<String>) {
        let active = tracker.activeSources
        let ids = Set(sourceOfProcess.values.map(\.id)).union(active)
        let lines = ids.sorted().map { id -> String in
            let label = knownSources[id].map { $0.name == id ? id : "\($0.name) (\(id))" } ?? id
            var state = active.contains(id) ? "playing"
                : audible.contains(id) ? "starting"
                : "output open, silent"
            if ignoredSourceIDs.contains(id) { state += ", ignored" }
            if detectionMethod == .playbackSignals, awake.contains(id) { return "\(label) — \(state) (tells macOS it is playing)" }
            if detectionMethod == .playbackSignals, announcingSourceIDs.contains(id) {
                return "\(label) — \(state) (not telling macOS it is playing)"
            }
            guard let level = levels[id] else { return "\(label) — \(state)" }
            let dBFS = level > 0 ? String(format: "%.0f dBFS", 20 * log10(level)) : "silence"
            return "\(label) — \(state) (\(dBFS))"
        }
        report.withLock { $0.lines = lines }
    }
}
