import Foundation
@testable import AutoHushKit

/// Records what the arbiter asks of the volume leveler: its lowerings, each
/// taking effect, as the real one's on an output with a volume control.
/// There is nothing else to ask: nothing puts the volume back.
final class RecordingVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var _log: [String] = []
    var log: [String] { lock.withLock { _log } }

    func lower(by decibels: Float) -> Bool {
        lock.withLock {
            _log.append("lower \(decibels)")
            return true
        }
    }
}
