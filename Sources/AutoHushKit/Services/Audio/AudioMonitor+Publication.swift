import CoreAudio
import Foundation
import os

// AudioMonitor: what it reports.
extension AudioMonitor {
    func publishActiveSources() {
        let active = tracker.activeSources
            .map { id in
                var source = knownSources[id] ?? AudioSource(id: id, name: id)
                source.isMicrophoneOnly = configuration.pausesForMicrophone && !soundedSourceIDs.contains(id)
                source.isOpenOutputOnly = !source.isMicrophoneOnly && openOutputSourceIDs.contains(id)
                return source
            }
            .sortedByName()
        guard active != publishedActive else { return }
        publishedActive = active
        onActiveSourcesChange(active)
    }

    /// Whether an app counting only by its open output is the exception
    /// worth saying (`AudioSource.isOpenOutputOnly`): in AntiDot mode's
    /// "What apps tell macOS", and outside AntiDot mode while nothing is
    /// measured (no Audio Recording). Never while levels are measured, nor
    /// with "Open audio streams only", where every app counts so, as the
    /// user chose.
    var marksOpenOutput: Bool {
        switch detectionMethod {
        case .audioLevels: detectionMode != .audioLevel
        case .playbackSignals: true
        case .openStreams: false
        }
    }

    func publishReport(audible: Set<String>, levels: [String: Float], verdicts: [String: Bool]) {
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
