import CoreAudio
import Foundation
import os

// AudioMonitor: each look at which apps play.
extension AudioMonitor {
    func tick() {
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

    private func evaluate(at now: Date) {
        let measured = levelMeter?.drainLevels() ?? [:]
        let peaks = measured.mapValues(\.peak)
        updateDetectionMode(peaks: peaks, at: now)
        updateResumeLevel(levels: measured, at: now)
        notePlayerHearing(levels: measured, at: now)

        var audible: Set<String> = []
        var levels: [String: Float] = [:]
        let judgement = judgePlaybackSignals(at: now)
        /// The verdicts that decided: only for what wasn't measured.
        var verdicts: [String: Bool] = [:]
        // Silence counts only while measured: a tap made again starts afresh.
        // Without levels (AntiDot mode, open streams), no tap was released.
        silentSince = detectionMode == .audioLevel ? silentSince.filter { peaks[$0.key] != nil } : [:]
        if detectionMode != .audioLevel { quietProcesses = [] }
        var released: Set<AudioObjectID> = []
        var woken: Set<AudioObjectID> = []
        for process in candidates {
            guard let source = sourceOfProcess[process.objectID] else { continue }
            let announcing = judgement?.verdicts[source.id] == true
            if quietProcesses.contains(process.objectID) {
                // Released for its silence: silent until it says it plays,
                // or is heard as it's listened to again (`quietListenInterval`).
                let heard = peaks[process.objectID].map { $0 >= configuration.audibleThreshold } ?? false
                if announcing || heard {
                    woken.insert(process.objectID)
                    // An ignored app's can't pause the music, so it isn't
                    // what the listen is for (`quietProcessesToListen`).
                    if quietListen.until != nil, !ignoredSourceIDs.contains(source.id) { quietListen.heard = true }
                }
                guard heard else { continue }
            }
            let peak = detectionMode == .audioLevel ? peaks[process.objectID] : nil
            // One that says it plays stays measured through its silence (a
            // call's quiet stretch), so what follows is heard.
            if let peak, noteSilence(of: process.objectID, peak: peak, at: now), !announcing { released.insert(process.objectID) }
            if let peak { levels[source.id] = max(levels[source.id] ?? 0, peak) }
            let verdict = peak == nil ? judgement?.verdicts[source.id] : nil
            if let verdict { verdicts[source.id] = verdict }
            if isAudible(peak: peak, verdict: verdict) {
                audible.insert(source.id)
            }
        }

        let tapsChanged = !released.isEmpty || !woken.isEmpty
        if tapsChanged {
            quietProcesses.formUnion(released)
            quietProcesses.subtract(woken)
            logger.debug("[monitor] taps released for silence: \(released.count, privacy: .public), made again: \(woken.count, privacy: .public)")
        }
        if updateQuietListen(at: now) || tapsChanged { updateMeteredProcesses(at: now) }

        // Before source events, so a pause decision in this tick sees it.
        updateLocalPlayback()
        updateStartConfirmation()

        // AntiDot mode: sound without video must last longer (see the type
        // comment); with open streams only, which can't tell video, any sound
        // (a shorter minimum). With nothing measured outside AntiDot mode,
        // each app waits AntiDot mode's minimum for what judged it: what it
        // tells macOS (the verdicts that decided; none for video), else its
        // open stream.
        var slowStarts: [String: TimeInterval] = switch detectionMethod {
        case .audioLevels where detectionMode == .audioLevel: [:]
        case .audioLevels: Dictionary(uniqueKeysWithValues: audible.compactMap { id -> (String, TimeInterval)? in
            guard verdicts[id] != nil else { return (id, configuration.startConfirmationWithOpenStreams) }
            return judgement?.showingVideo.contains(id) == true ? nil : (id, configuration.startConfirmationWithoutVideo)
        })
        case .playbackSignals: judgement.map { judgement in
            Dictionary(uniqueKeysWithValues: audible.subtracting(judgement.showingVideo).map {
                ($0, configuration.startConfirmationWithoutVideo)
            })
        } ?? [:]
        case .openStreams: Dictionary(uniqueKeysWithValues: audible.map { ($0, configuration.startConfirmationWithOpenStreams) })
        }
        // Pause for the microphone (Settings → Behavior): an app with its
        // microphone on counts as playing, sound or not, once it's been on a
        // second (sooner if its sound counts sooner).
        let bySound = audible
        if configuration.pausesForMicrophone {
            for id in microphoneSourceIDs {
                let bySound = audible.contains(id) ? slowStarts[id] ?? configuration.sourceStartConfirmation : .infinity
                slowStarts[id] = min(bySound, configuration.microphoneStartConfirmation)
                audible.insert(id)
            }
        }
        let (started, stopped) = tracker.update(audible: audible, at: now, startConfirmations: slowStarts)
        let active = tracker.activeSources
        soundedSourceIDs = soundedSourceIDs.union(bySound).intersection(active)
        if !started.isEmpty || !stopped.isEmpty {
            logger.debug("[monitor] +[\(started.sorted().joined(separator: ","), privacy: .public)] -[\(stopped.sorted().joined(separator: ","), privacy: .public)]")
        }
        for id in started.sorted() where !ignoredSourceIDs.contains(id) {
            events.yield(.source(id: id, isPlaying: true, heardSince: tracker.firstHeard(id)))
        }
        for id in stopped.sorted() where !ignoredSourceIDs.contains(id) {
            events.yield(.source(id: id, isPlaying: false, heardSince: nil))
        }

        // Forget sources that are neither tracked nor currently present.
        knownSources = knownSources.filter { tracker.isTracking($0.key) || presentSourceIDs.contains($0.key) }

        publishActiveSources()
        publishReport(audible: audible, levels: levels, verdicts: verdicts)
    }

    /// Notes a tapped source process's level: `true` once it has been silent
    /// for `silentTapRelease`, when its tap is to be released.
    private func noteSilence(of objectID: AudioObjectID, peak: Float, at now: Date) -> Bool {
        guard peak < configuration.audibleThreshold else {
            silentSince[objectID] = nil
            return false
        }
        let since = silentSince[objectID] ?? now
        guard now.timeIntervalSince(since) >= Self.silentTapRelease else {
            silentSince[objectID] = since
            return false
        }
        silentSince[objectID] = nil
        return true
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

    /// Tells the arbiter how long an app must play, at most, before it
    /// counts, as apps are judged now (see `evaluate`'s slow starts): a pause
    /// it takes over waits that long for apps still playing.
    private func updateStartConfirmation() {
        let judged = switch detectionMethod {
        case .audioLevels where detectionMode == .audioLevel: configuration.sourceStartConfirmation
        case .audioLevels: max(configuration.startConfirmationWithoutVideo, configuration.startConfirmationWithOpenStreams)
        case .playbackSignals: configuration.startConfirmationWithoutVideo
        case .openStreams: configuration.startConfirmationWithOpenStreams
        }
        let longest = configuration.pausesForMicrophone ? max(judged, configuration.microphoneStartConfirmation) : judged
        guard longest != publishedStartConfirmation else { return }
        publishedStartConfirmation = longest
        events.yield(.startConfirmation(longest))
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
    /// The media player playing alone leaves nothing to judge, and a new app
    /// starting is announced by a HAL change, which ticks at once.
    static func tickInterval(
        otherAppsRunning: Bool, isTracking: Bool, recentlyChanged: Bool, configuration: AppConfiguration
    ) -> TimeInterval {
        otherAppsRunning || isTracking || recentlyChanged
            ? configuration.activeSampleInterval
            : configuration.idleSampleInterval
    }
}
