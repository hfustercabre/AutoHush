import AutoHushKit
import Foundation
import Testing
import AutoHushTestSupport
@testable import PlayerCheck

/// The app muted for a test of its sound: it looks again every 0.1 s only
/// until its first mute works.
@Suite("playercheck: muting it for a test", .readOnlyRun, .waitsTimeLimit)
struct TestMuteTests {
    @Test("muted at once: nothing is left to look for")
    func mutedAtOnce() {
        let muter = TestMuteMuter(works: true)
        let mute = TestMute(pid: 4242, muter: muter, hasSound: { _ in true })
        #expect(mute.start())
        #expect(!mute.isRetrying)
        #expect(muter.mutes == 1)
        #expect(!mute.stop())
    }

    @Test("not muted yet (no sound, or a mute refused): it looks again until one works, then stops looking")
    func retries() async throws {
        let silent = TestMute(pid: 4242, muter: TestMuteMuter(works: true), hasSound: { _ in false })
        #expect(silent.start()) // nothing to hear yet
        #expect(silent.isRetrying)
        #expect(!silent.stop())
        #expect(!silent.isRetrying)

        let muter = TestMuteMuter(works: false)
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
