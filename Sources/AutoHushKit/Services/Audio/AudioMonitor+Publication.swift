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
                return source
            }
            .sortedByName()
        guard active != publishedActive else { return }
        publishedActive = active
        onActiveSourcesChange(active)
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
