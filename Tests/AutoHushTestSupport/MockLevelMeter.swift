import CoreAudio
import Foundation
import Testing
import AutoHushKit

// Stand-ins for what AudioMonitor reads from macOS: the audio processes, their
// levels, the power assertions and the System Audio Recording permission.
// Shared by the engine's tests and the app's (the player session's pipelines).

package final class MockLevelMeter: AudioLevelMetering, @unchecked Sendable {
    package init() {}

    private let lock = NSLock()
    private var _peaks: [AudioObjectID: Float] = [:]
    private var _followed: [AudioObjectID: (peak: Float, plays: Locked<Bool>)] = [:]
    private var _metered: Set<AudioObjectID> = []
    private var _stopAllCount = 0

    /// Peaks reported for every metered process (missing entries read as 0).
    package var peaks: [AudioObjectID: Float] {
        get { lock.withLock { _peaks } }
        set { lock.withLock { _peaks = newValue } }
    }

    /// The process's peak follows a player: `peak` while it plays, 0 while
    /// it doesn't, whatever `peaks` says.
    package func follow(_ objectID: AudioObjectID, playing plays: Locked<Bool>, peak: Float) {
        lock.withLock { _followed[objectID] = (peak, plays) }
    }

    package var lastMetered: Set<AudioObjectID> { lock.withLock { _metered } }
    package var stopAllCount: Int { lock.withLock { _stopAllCount } }

    /// Waits until exactly these processes are metered, e.g. after a delayed release.
    package func waitUntilMetered(_ objectIDs: Set<AudioObjectID>, sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = TestWait.deadline
        while lastMetered != objectIDs {
            guard Date() < deadline else {
                TestWait.timedOut(at: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    package func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        lock.withLock { _metered = objectIDs }
    }

    package func drainPeaks() -> [AudioObjectID: Float] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: _metered.map { id in
                (id, _followed[id].map { $0.plays.value ? $0.peak : 0 } ?? _peaks[id] ?? 0)
            })
        }
    }

    package func stopAll() {
        lock.withLock {
            _metered = []
            _stopAllCount += 1
        }
    }
}
