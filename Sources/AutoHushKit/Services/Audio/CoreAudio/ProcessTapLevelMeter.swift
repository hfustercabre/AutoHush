import CoreAudio
import Foundation
import OSLog

// MARK: - Level metering protocol

/// Measures how loud individual audio processes actually are, as opposed to
/// whether they merely hold an output stream open.
package protocol AudioLevelMetering: AnyObject, Sendable {
    /// Ensures exactly `objectIDs` are metered; taps for other processes are torn down.
    func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>)
    /// Peak absolute sample value per metered process since the previous call.
    /// Processes whose tap could not be created are absent from the result.
    func drainPeaks() -> [AudioObjectID: Float]
    /// Peak and average level per metered process since the previous call.
    func drainLevels() -> [AudioObjectID: AudioLevel]
    func stopAll()
}

extension AudioLevelMetering {
    /// For a meter that only knows peaks: each one as its average too.
    package func drainLevels() -> [AudioObjectID: AudioLevel] {
        drainPeaks().mapValues { AudioLevel(peak: $0, rms: $0) }
    }
}

// MARK: - CoreAudio process tap implementation

/// Meters processes with CoreAudio process taps (macOS 14.2+).
///
/// Each metered process gets a private, unmuted tap wrapped in a private
/// aggregate device whose IO block records the peak and average (RMS) sample
/// level. Samples are inspected in memory only to compute those levels;
/// nothing is stored or sent.
///
/// Requires the "System Audio Recording" privacy permission. When it is denied
/// macOS still creates the tap but delivers silence, so callers must not treat
/// all-zero peaks as proof that a process is silent until a non-zero sample has
/// been seen at least once (see `AudioMonitor`).
///
/// Not thread-safe except for the IO blocks: call every method from one queue.
package final class ProcessTapLevelMeter: AudioLevelMetering, @unchecked Sendable {
    package init() {}

    private let logger = AutoHushLogger(category: "LevelMeter")
    private let ioQueue = DispatchQueue(label: "AutoHush.LevelMeter.io", qos: .userInitiated)
    private var taps: [AudioObjectID: ProcessTap] = [:]
    /// Processes whose tap failed to start: not retried while they're to be
    /// metered, only once they're metered again after a call without them.
    private var failed: Set<AudioObjectID> = []

    package func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        for (objectID, tap) in taps where !objectIDs.contains(objectID) {
            tap.invalidate()
            taps[objectID] = nil
        }
        failed.formIntersection(objectIDs)

        for objectID in objectIDs where taps[objectID] == nil && !failed.contains(objectID) {
            do {
                taps[objectID] = try ProcessTap(processObjectIDs: [objectID], ioQueue: ioQueue)
                logger.debug("[meter] tapping process object \(objectID, privacy: .public)")
            } catch {
                failed.insert(objectID)
                logger.error("[meter] tap for process object \(objectID, privacy: .public) failed: \(error)")
            }
        }
    }

    package func drainPeaks() -> [AudioObjectID: Float] {
        taps.mapValues { $0.drainLevel().peak }
    }

    /// Peak and average level per metered process since the previous call
    /// (the volume-curve tool, and leveling the music).
    package func drainLevels() -> [AudioObjectID: AudioLevel] {
        taps.mapValues { $0.drainLevel() }
    }

    package func stopAll() {
        taps.values.forEach { $0.invalidate() }
        taps.removeAll()
        failed.removeAll()
    }

    deinit { stopAll() }
}
