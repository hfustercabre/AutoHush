import Foundation
@testable import AutoHushKit

/// Records what the arbiter asks of the volume leveler. As the real one,
/// it lowers once until put back, and a put-back with another lowering's
/// token does nothing (it isn't logged).
final class RecordingVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var _log: [String] = []
    private var lowered: UUID?
    var log: [String] { lock.withLock { _log } }

    func lower(by decibels: Float) -> UUID? {
        lock.withLock {
            _log.append("lower \(decibels)")
            guard lowered == nil else { return nil }
            lowered = UUID()
            return lowered
        }
    }

    func restore(over duration: TimeInterval, lowered token: UUID) {
        putBack(token, as: "restore over \(duration)")
    }

    func restoreNow(lowered token: UUID) {
        putBack(token, as: "restore now")
    }

    func restoreNow() {
        lock.withLock {
            _log.append("restore now (any)")
            lowered = nil
        }
    }

    private func putBack(_ token: UUID, as entry: String) {
        lock.withLock {
            guard token == lowered else { return }
            _log.append(entry)
            lowered = nil
        }
    }
}
