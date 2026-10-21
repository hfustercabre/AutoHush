import CoreAudio
import Foundation

// AudioMonitor: how loud the music was before AutoHush's pause, and the
// apps during it (Settings → Behavior; `ResumeLevel`).
extension AudioMonitor {
    /// Feeds this look's levels to `resumeLevel`: the music's own, while
    /// it's heard, and the other apps' together while any is heard (the
    /// ignored ones and calls aside).
    func updateResumeLevel(levels: [AudioObjectID: AudioLevel], at now: Date) {
        guard configuration.levelsMusic, detectionMode == .audioLevel else { return }
        let music = playerProcesses.compactMap { levels[$0] }
        if let loudest = music.map(\.peak).max(), loudest >= configuration.audibleThreshold {
            resumeLevel.noteMusic(rms: Self.combined(music.map(\.rms)), at: now)
        }
        let heard = sourceOfProcess.compactMap { objectID, source -> AudioLevel? in
            guard !ignoredSourceIDs.contains(source.id), !callSourceIDs.contains(source.id),
                  let level = levels[objectID], level.peak >= configuration.audibleThreshold else { return nil }
            return level
        }
        if !heard.isEmpty { resumeLevel.noteApps(rms: Self.combined(heard.map(\.rms))) }
    }

    /// Several processes' average levels as one (their power summed).
    private static func combined(_ levels: [Float]) -> Float {
        levels.map { $0 * $0 }.reduce(0, +).squareRoot()
    }
}
