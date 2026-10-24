import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Playing silently

    /// Whether the player is heard, as the arbiter asks it (`hearsPlayer`).
    final class Hearing: @unchecked Sendable {
        // Read and written only under `lock`.
        private let lock = NSLock()
        private var heard: Bool?
        private var asked = 0
        init(_ heard: Bool?) { self.heard = heard }
        var isHeard: Bool? {
            get { lock.withLock { heard } }
            set { lock.withLock { heard = newValue } }
        }
        var timesAsked: Int { lock.withLock { asked } }
        func ask() -> Bool? { lock.withLock { asked += 1; return heard } }
    }

    private func makeHearingArbiter(_ player: MockMusicPlayer, hearing: Hearing, scheduler: ManualDebounceScheduler,
                                    published: LastPublished) -> PlaybackArbiter {
        PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                        onPlaybackStateChange: { published.set($0) }, hearsPlayer: { hearing.ask() })
    }

    @Test("a player that says it plays but isn't heard isn't paused: it's playing silently, listened to again every 2 s, and paused once heard")
    func silentPlayerNotPaused() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(false) // a muted trailer
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { published.state == .playingSilently }
        #expect(await player.pauseCallCount == 0)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval)

        await scheduler.completeNext() // still silent: listened to again later
        await TestWait.until { hearing.timesAsked == 2 && scheduler.scheduledDelays.count == 2 }
        #expect(await player.pauseCallCount == 0)

        hearing.isHeard = true // the real thing starts
        await scheduler.completeNext()
        await TestWait.until { await player.pauseCallCount == 1 }
        await TestWait.until { published.state == .pausedByMonitor }
        #expect(published.state == .pausedByMonitor)
    }

    @Test("a player that can't be listened to (AntiDot mode) is paused as before")
    func unheardPlayerPausedWithoutLevels() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: Hearing(nil), scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        #expect(published.state != .playingSilently)
    }

    @Test("the menu opening listens to a playing player: silent, it's playing silently; heard again, it's playing")
    func menuOpeningListens() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(false)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.refreshPlaybackState()
        #expect(published.state == .musicPlaying)

        await arbiter.checkPlayerHeard()
        #expect(published.state == .playingSilently)
        hearing.isHeard = true
        await arbiter.checkPlayerHeard()
        #expect(published.state == .musicPlaying)
    }

    @Test("a player playing silently that pauses or closes its output is no longer playing silently")
    func silenceForgotten() async {
        for byOutput in [false, true] {
            let player = MockMusicPlayer()
            let scheduler = ManualDebounceScheduler(), published = LastPublished()
            let arbiter = makeHearingArbiter(player, hearing: Hearing(false), scheduler: scheduler, published: published)
            await arbiter.refreshPlaybackState()
            await arbiter.checkPlayerHeard()
            #expect(published.state == .playingSilently)
            await arbiter.handlePlayerStateChange(.playing) // said again: still silent
            #expect(published.state == .playingSilently)
            if byOutput {
                await arbiter.handleLocalPlaybackChange(false)
                #expect(published.state == .playingElsewhere)
                await arbiter.handleLocalPlaybackChange(true)
                #expect(published.state == .musicPlaying)
            } else {
                await arbiter.handlePlayerStateChange(.paused)
                #expect(published.state == .musicIdle)
                await arbiter.handlePlayerStateChange(.playing)
                #expect(published.state == .musicPlaying)
            }
        }
    }
}
