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
        private var asked: [Bool] = []
        private var askedSince: [Date?] = []
        private var hook: (@Sendable () async -> Void)?
        init(_ hearing: PlayerHearing) { self.hearing = hearing }
        /// Runs as it's asked, before it answers (something changing while
        /// the player is measured).
        var beforeAnswer: (@Sendable () async -> Void)? {
            get { lock.withLock { hook } }
            set { lock.withLock { hook = newValue } }
        }
        func answer(listening: Bool, since: Date? = nil) async -> PlayerHearing {
            await beforeAnswer?()
            return ask(listening: listening, since: since)
        }
        var now: PlayerHearing {
            get { lock.withLock { hearing } }
            set { lock.withLock { hearing = newValue } }
        }
        var timesAsked: Int { lock.withLock { asked.count } }
        /// Whether each ask let it listen with a tap of its own.
        var listened: [Bool] { lock.withLock { asked } }
        /// From when each ask counted the player's sound.
        var since: [Date?] { lock.withLock { askedSince } }
        func ask(listening: Bool, since: Date? = nil) -> PlayerHearing {
            lock.withLock { asked.append(listening); askedSince.append(since); return hearing }
        }
    }

    private func makeHearingArbiter(_ player: MockMusicPlayer, hearing: Hearing, scheduler: ManualDebounceScheduler,
                                    published: LastPublished) -> PlaybackArbiter {
        PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                        onPlaybackStateChange: { published.set($0) }, hearsPlayer: { await hearing.answer(listening: $0, since: $1) })
    }

    @Test("a player that says it plays but isn't heard isn't paused: it's playing silently, asked again every second, never listening on its own, and paused once heard")
    func silentPlayerNotPaused() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent) // a muted trailer
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        #expect(hearing.listened.allSatisfy { !$0 }) // no tap of its own on a pause's way
    }

    @Test("a player playing silently stays so when it can no longer be measured (the other app's output closed): it isn't paused")
    func silentStaysSilentUnmeasured() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        #expect(published.state != .playingSilently)
    }

    @Test("the menu opening listens to a playing player: silent, it's playing silently; heard again, it's playing")
    func menuOpeningListens() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.refreshPlaybackState()
        #expect(published.state == .musicPlaying)

        await arbiter.checkPlayerHeard()
        await arbiter.waitUntilIdle() // the listen runs in a task of its own
        #expect(published.state == .playingSilently)
        hearing.now = .heard
        await arbiter.checkPlayerHeard()
        await arbiter.waitUntilIdle() // the listen runs in a task of its own
        #expect(published.state == .musicPlaying)
        #expect(hearing.listened == [true, true])
    }

    @Test("a player playing silently that pauses or closes its output is no longer playing silently")
    func silenceForgotten() async {
        for byOutput in [false, true] {
            let player = MockMusicPlayer()
            let scheduler = ManualDebounceScheduler(), published = LastPublished()
            let arbiter = makeHearingArbiter(player, hearing: Hearing(.silent), scheduler: scheduler, published: published)
            await arbiter.refreshPlaybackState()
            await arbiter.checkPlayerHeard()
            await arbiter.waitUntilIdle() // the listen runs in a task of its own
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

    @Test("a player playing silently is paused the moment the monitor hears it, not at the next look")
    func silentPlayerPausedWhenHeard() async {
        let player = MockMusicPlayer()
        let hearing = Hearing(.silent)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: hearing, scheduler: scheduler, published: published)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval }
        await arbiter.waitForPause()
        #expect(published.state == .musicIdle)
        #expect(await player.pauseCallCount == 0)
    }

    @Test("the menu opening finds a player known only by its open output silent: shown as not playing")
    func menuSilentWithoutState() async {
        let player = MockMusicPlayer()
        await player.setStatesItself(false)
        let scheduler = ManualDebounceScheduler(), published = LastPublished()
        let arbiter = makeHearingArbiter(player, hearing: Hearing(.silent), scheduler: scheduler, published: published)
        await arbiter.refreshPlaybackState()
        await arbiter.checkPlayerHeard()
        await arbiter.waitUntilIdle() // the listen runs in a task of its own
        #expect(published.state == .musicIdle)
    }
}
