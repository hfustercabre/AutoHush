import AutoHushKit
import Foundation
import Testing
import AutoHushTestSupport
@testable import PlayerCheck

/// Stands in for the muter: whether a mute works, and how many were asked.
private final class Muter: AudioMuting, @unchecked Sendable {
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

/// The app muted for a test of its sound: it looks again every 0.1 s only
/// until its first mute works.
@Suite("playercheck: muting it for a test", .readOnlyRun)
struct TestMuteTests {
    @Test("muted at once: nothing is left to look for")
    func mutedAtOnce() {
        let muter = Muter(works: true)
        let mute = TestMute(pid: 4242, muter: muter, hasSound: { _ in true })
        #expect(mute.start())
        #expect(!mute.isRetrying)
        #expect(muter.mutes == 1)
        #expect(!mute.stop())
    }

    @Test("not muted yet (no sound, or a mute refused): it looks again until one works, then stops looking")
    func retries() async throws {
        let silent = TestMute(pid: 4242, muter: Muter(works: true), hasSound: { _ in false })
        #expect(silent.start()) // nothing to hear yet
        #expect(silent.isRetrying)
        #expect(!silent.stop())
        #expect(!silent.isRetrying)

        let muter = Muter(works: false)
        let refused = TestMute(pid: 4242, muter: muter, hasSound: { _ in true })
        #expect(!refused.start())
        #expect(refused.isRetrying)
        muter.letMute()
        // Tried again half a second after the refusal.
        await TestWait.until { !refused.isRetrying }
        #expect(muter.mutes >= 2)
        #expect(refused.stop()) // a mute failed meanwhile
    }
}
