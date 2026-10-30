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

    /// The leveler's logger: its measurements go with its own lines (under
    /// Player in the Logs window), not with the monitor's.
    private static let levelLogger = AutoHushLogger(category: "VolumeLeveler")

    /// Whether the music is paused by AutoHush: its loudness just before
    /// is noted, and the apps' during the pause (with `levelsMusic`).
    func setMusicPaused(_ paused: Bool) {
        queue.async {
            if !paused, let apps = self.resumeLevel.appsLevel {
                Self.levelLogger.info("[level] the apps’ loudness during the pause: \(Self.dBFS(apps), privacy: .public) dBFS")
            }
            self.resumeLevel.setMusicPaused(paused, at: self.clock())
            if paused, let reference = self.resumeLevel.reference {
                Self.levelLogger.info("[level] the music’s loudness at the pause: \(Self.dBFS(reference), privacy: .public) dBFS")
            }
        }
    }

    /// How far (dB, below 0) to lower the Mac's volume as the music
    /// resumes: `nil` unless the apps it was paused for were quieter, or
    /// with `levelsMusic` off or levels unmeasured (AntiDot mode).
    func resumeOffsetDB() async -> Float? {
        await queue.run {
            guard self.configuration.levelsMusic, self.detectionMode == .audioLevel else { return nil }
            return self.resumeLevel.offsetDB(maxCut: self.configuration.levelingMaxCutDB, minCut: self.configuration.levelingMinCutDB)
        }
    }

    private static func dBFS(_ rms: Float) -> String {
        String(format: "%.1f", 20 * log10(max(rms, 0.0001)))
    }
}
