import CoreAudio
import Foundation

/// Tells whether an app can be heard right now, for a player whose own
/// controls can't say: during YouTube Music's ads its Play/Pause reads "Play"
/// while the ad plays. An open output doesn't tell either, since a paused
/// page keeps its output open, silent, for several seconds.
package protocol AudioLevelProbing: Sendable {
    /// Listens to every audio process the app running as `appPID` owns, for
    /// a moment (it blocks meanwhile); `false` when it's silent or can't be
    /// measured (no System Audio Recording permission).
    func isAudible(appPID: pid_t) -> Bool
}

/// Listens through process taps that exist only while it listens
/// (`ProcessTapLevelMeter`); nothing is kept.
package struct ProcessTapLevelProbe: AudioLevelProbing {
    /// How long it listens: several of the taps' buffers.
    package static let listeningTime: TimeInterval = 0.5
    /// The peak that counts as sound.
    private let threshold: Float

    /// `threshold`: by default AutoHush's own, from Settings' default.
    package init(threshold: Float = AppConfiguration().audibleThreshold) {
        self.threshold = threshold
    }

    package func isAudible(appPID: pid_t) -> Bool {
        let processes = ProcessTapMuter.processObjects(ownedBy: appPID)
        guard !processes.isEmpty else { return false }
        let meter = ProcessTapLevelMeter()
        meter.setMeteredProcesses(Set(processes))
        defer { meter.stopAll() }
        Thread.sleep(forTimeInterval: Self.listeningTime)
        return meter.drainPeaks().values.contains { $0 >= threshold }
    }
}
