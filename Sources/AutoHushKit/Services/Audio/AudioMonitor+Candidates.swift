import CoreAudio
import Foundation

// AudioMonitor: the processes with their sound on, whose they are, and
// which of them are measured.
extension AudioMonitor {
    func refreshCandidates(at now: Date) {
        needsRefresh = false
        lastRefresh = now
        let ownPID = getpid()
        let processes = snapshotProvider.activeProcesses(includingInputOnly: configuration.pausesForMicrophone)
            .filter { $0.pid != ownPID }
        candidates = processes.filter(\.isRunningOutput)
        playerProcesses = Set(candidates.filter { configuration.isMusicPlayer($0.bundleID) }.map(\.objectID))
        sourceOfProcess = [:]
        // A process without a bundle ID (a command-line player) counts as
        // the app that owns it, e.g. Terminal; one no app owns (a system
        // daemon) is left with an empty ID and doesn't count.
        for process in candidates {
            guard let source = owningSource(of: process) else { continue }
            if configuration.isMusicPlayer(source.id) { playerProcesses.insert(process.objectID) }
            // An excluded owner (e.g. the media player's helper) excludes its processes too.
            guard configuration.isMediaSource(source.id) else { continue }
            sourceOfProcess[process.objectID] = source
            knownSources[source.id] = source
        }
        presentSourceIDs = Set(sourceOfProcess.values.map(\.id))
        updateMicrophoneSources(among: processes)
        // A released process whose output closed is tapped again when it opens.
        let present = Set(candidates.map(\.objectID))
        quietProcesses = quietProcesses.filter { present.contains($0) }
        updateCalls()
        updateMeteredProcesses(at: now)
    }

    /// The apps with their microphone on, among `processes` (the media
    /// player's aside), as their sound's owner is found.
    private func updateMicrophoneSources(among processes: [AudioProcessInfo]) {
        microphoneSourceIDs = []
        for process in processes where process.isRunningInput {
            // Only its microphone on: its owner, found as for a playing one.
            guard let source = sourceOfProcess[process.objectID] ?? owningSource(of: process),
                  configuration.isMediaSource(source.id) else { continue }
            microphoneSourceIDs.insert(source.id)
            knownSources[source.id] = source
        }
    }

    /// The app that owns `process` (`sourceIdentifier`), or its own bundle
    /// ID; `nil` when that ID already rules it out (the media player's, an
    /// app that never counts). The owner may be ruled out still.
    private func owningSource(of process: AudioProcessInfo) -> AudioSource? {
        guard process.bundleID.isEmpty || configuration.isMediaSource(process.bundleID) else { return nil }
        return sourceIdentifier?.source(for: process) ?? AudioSource(id: process.bundleID, name: process.bundleID)
    }

    /// Tells the arbiter which apps have their microphone on (calls): only
    /// playing ones while Pause for the microphone is off.
    private func updateCalls() {
        let calls = microphoneSourceIDs.subtracting(ignoredSourceIDs)
        for id in calls.subtracting(callSourceIDs).sorted() { events.yield(.call(id: id, inCall: true)) }
        for id in callSourceIDs.subtracting(calls).sorted() { events.yield(.call(id: id, inCall: false)) }
        callSourceIDs = calls
    }

    /// Taps are created only when they matter (see the type comment) and can
    /// deliver samples: with the permission granted, or when it cannot be
    /// read (then samples decide).
    var shouldMeterLevels: Bool {
        detectionMethod == .audioLevels && audioLevelsNeeded
            && (permissionStatus == nil || permissionStatus == .granted)
    }

    func updateMeteredProcesses(at now: Date) {
        guard let levelMeter else { return }
        // The player is tapped only to prove the permission when TCC cannot be read.
        let verifiesWithPlayer = permissionStatus == nil && detectionMode != .audioLevel
        // The quiet ones only while they're listened to again (`quietListenInterval`).
        let listened = quietListen.until == nil ? [] : quietProcessesToListen
        var metered = shouldMeterLevels ? candidates.filter {
            (sourceOfProcess[$0.objectID] != nil && (!quietProcesses.contains($0.objectID) || listened.contains($0.objectID)))
                || (verifiesWithPlayer && playerProcesses.contains($0.objectID))
        } : []
        let tapsPlayer = metered.contains { playerProcesses.contains($0.objectID) }
        playerTapSince = tapsPlayer ? (playerTapSince ?? now) : nil
        // The music too while another app is measured: whether it's heard
        // (`playerHearing`) and, leveling the music, its loudness. Not for
        // the music alone, so the recording indicator isn't on for it, nor
        // for a quiet app's listen alone: one heard there is measured on.
        if detectionMode == .audioLevel, !tapsPlayer,
           metered.contains(where: { sourceOfProcess[$0.objectID] != nil && !quietProcesses.contains($0.objectID) }) {
            metered += candidates.filter { playerProcesses.contains($0.objectID) }
        }
        // May block while macOS shows the System Audio Recording prompt.
        levelMeter.setMeteredProcesses(Set(metered.map(\.objectID)))
    }
}
