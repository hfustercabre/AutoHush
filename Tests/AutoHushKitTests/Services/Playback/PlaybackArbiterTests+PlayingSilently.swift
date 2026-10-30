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
        private var hearing: PlayerHearing
        private var askedSince: [Date?] = []
        private var hook: (@Sendable () async -> Void)?
        init(_ hearing: PlayerHearing) { self.hearing = hearing }
        /// Runs as it's asked, before it answers (something changing while
        /// the player is measured).
        var beforeAnswer: (@Sendable () async -> Void)? {
            get { lock.withLock { hook } }
            set { lock.withLock { hook = newValue } }
        }
        func answer(since: Date? = nil) async -> PlayerHearing {
            await beforeAnswer?()
            return ask(since: since)
        }
        var now: PlayerHearing {
            get { lock.withLock { hearing } }
            set { lock.withLock { hearing = newValue } }
        }
        var timesAsked: Int { lock.withLock { askedSince.count } }
        /// From when each ask counted the player's sound.
        var since: [Date?] { lock.withLock { askedSince } }
        func ask(since: Date? = nil) -> PlayerHearing {
            lock.withLock { askedSince.append(since); return hearing }
        }
    }

    private func makeHearingArbiter(_ player: MockMusicPlayer, hearing: Hearing, scheduler: ManualDebounceScheduler,
                                    published: LastPublished) -> PlaybackArbiter {
        PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                        onStatusUpdate: statuses(playback: { published.set($0) }), hearsPlayer: { await hearing.answer(since: $0) })
    }

    @Test("a player that says it plays but isn't heard isn't paused: it's playing silently, asked again every second, and paused once heard")
    func silentPlayerNotPaused() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent) // a muted trailer
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { published.state == .playingSilently }
        #expect(await player.pauseCallCount == 0)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval)

        await scheduler.completeNext() // still silent: listened to again later
        await TestWait.until { hearing.timesAsked == 2 && scheduler.scheduledDelays.count == 2 }
        #expect(await player.pauseCallCount == 0)

        hearing.now = .heard // the real thing starts
        await scheduler.completeNext()
        await TestWait.until { await player.pauseCallCount == 1 }
        await TestWait.until { published.state == .pausedByMonitor }
        #expect(published.state == .pausedByMonitor)
    }

    @Test("a player playing silently stays so when it can no longer be measured (the other app's output closed): it isn't paused")
    func silentStaysSilentUnmeasured() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { published.state == .playingSilently }
        hearing.now = .unknown
        await scheduler.completeNext()
        await TestWait.until { hearing.timesAsked == 2 && scheduler.scheduledDelays.count == 2 }
        #expect(await player.pauseCallCount == 0)
        #expect(published.state == .playingSilently)
    }

    @Test("a player measured too briefly to tell waits the rest before it's paused, and is paused at once when heard meanwhile")
    func briefMeasureWaits() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.measuring(remaining: 0.4))
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { scheduler.scheduledDelays.last == 0.4 }
        #expect(await player.pauseCallCount == 0)
        #expect(published.state != .playingSilently)

        hearing.now = .heard
        await scheduler.completeNext()
        await TestWait.until { await player.pauseCallCount == 1 }
    }

    @Test("a player that can't be listened to (AntiDot mode) is paused as before")
    func unheardPlayerPausedWithoutLevels() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: Hearing(.unknown), scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        #expect(published.state != .playingSilently)
    }

    @Test("a player playing silently that pauses or closes its output is no longer playing silently")
    func silenceForgotten() async {
        for byOutput in [false, true] {
            let player = MockMusicPlayer()
            let scheduler = ManualDebounceScheduler(), published = LastPublished()
            let arbiter = makeHearingArbiter(player, hearing: Hearing(.silent), scheduler: scheduler, published: published)
            await arbiter.sourceChanged("org.example.viewer", playing: true) // measured alongside it: silent
            await TestWait.until { published.state == .playingSilently }
            await arbiter.handlePlayerStateChange(.playing) // said again: still silent
            #expect(published.state == .playingSilently)
            if byOutput {
                await arbiter.handleLocalPlaybackChange(false)
                #expect(published.state == .playingElsewhere)
            } else {
                await arbiter.handlePlayerStateChange(.paused)
                #expect(published.state == .musicIdle)
            }
        }
    }

    @Test("once the other apps stop, nothing measures a player playing silently: it shows as playing, and nothing is paused or played")
    func silenceForgottenWhenAppsStop() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: Hearing(.silent), scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { published.state == .playingSilently }
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(published.state == .musicPlaying)
        #expect(await player.pauseCallCount == 0)
        #expect(await player.playCallCount == 0)
    }

    @Test("a player playing silently is paused the moment the monitor hears it, not at the next look")
    func silentPlayerPausedWhenHeard() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { published.state == .playingSilently }
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitForPause()
        await player.setState(.playing) // it starts again before the look that was pending
        await scheduler.completeNext() // that look, called off
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("not heard, a player known to play only by its open output (it reports no state) shows as not playing, not as playing silently")
    func silentWithoutStateNotPlaying() async {
        let player = MockMusicPlayer()
        await player.setStatesItself(false)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: Hearing(.silent), scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval }
        await arbiter.waitForPause()
        #expect(published.state == .musicIdle)
        #expect(await player.pauseCallCount == 0)
    }

}
