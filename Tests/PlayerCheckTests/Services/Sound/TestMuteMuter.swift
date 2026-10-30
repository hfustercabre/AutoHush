import AutoHushKit
import Foundation

/// Stands in for the muter: whether a mute works, and how many were asked.
final class TestMuteMuter: AudioMuting, @unchecked Sendable {
    // Read and written only under `lock`.
    private let lock = NSLock()
    private var works: Bool
    private var asked = 0
    init(works: Bool) { self.works = works }
    var mutes: Int { lock.withLock { asked } }
    func letMute() { lock.withLock { works = true } }
    func mute(appPID: pid_t) -> Bool {
        lock.withLock {
            asked += 1
            return works
        }
    }
    func unmute(appPID: pid_t) {}
}
