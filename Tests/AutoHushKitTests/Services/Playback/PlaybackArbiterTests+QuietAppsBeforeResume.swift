import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Quiet apps before a resume (R2, 2026-10-27)

    @Test("an app that went quiet and is heard just before the resume keeps the music paused as long as an app takes to count, then the resume looks again")
    func resumeWaitsForQuietAppHeard() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let listens = Locked(0)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      quietAppPlaysAgain: { listens.withLock { $0 += 1; return $0 == 1 } })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        let wait = await arbiter.startConfirmation + PlaybackArbiter.takeOverMargin
        await TestWait.until { scheduler.scheduledDelays.contains(wait) }
        #expect(await player.playCallCount == 0)
        #expect(listens.value == 1)

        // It didn't come to count as playing: the music comes back.
        await scheduler.completeNext()
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(listens.value == 2)
        #expect(await player.state == .playing)
    }

    @Test("a quiet app counting as playing during that wait keeps the music paused")
    func quietAppCountingCallsOffResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      quietAppPlaysAgain: { true })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { !scheduler.scheduledDelays.isEmpty }
        await arbiter.sourceChanged("com.example.game", playing: true) // counted now
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }

    @Test("Auto-Pause turned off brings the music back at once, without listening to the quiet apps")
    func autoPauseOffSkipsQuietListen() async {
        let player = MockMusicPlayer()
        let listens = Locked(0)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing,
                                      quietAppPlaysAgain: { listens.withLock { $0 += 1 }; return true })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.setAutoPauseEnabled(false)
        await TestWait.until { await player.playCallCount == 1 }
        #expect(listens.value == 0)
    }
}
