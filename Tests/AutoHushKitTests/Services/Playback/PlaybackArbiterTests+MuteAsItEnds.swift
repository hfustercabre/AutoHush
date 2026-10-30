import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    @Test("a mute made just as the other app stops is lifted at once, not left with nothing to lift it")
    func muteAsAppsStopLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        // The app stops while the tap is made, and its resume runs then (it plays: nothing to resume).
        mute.whileMuting = {
            await arbiter.sourceChanged("org.videolan.vlc", playing: false)
            if let resume = await arbiter.pendingResumeTask { await resume.value }
        }
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(published.state == .musicPlaying)
    }

    @Test("a mute made just as Auto-Pause is turned off is lifted at once")
    func muteAsAutoPauseOffLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        mute.whileMuting = {
            await arbiter.setAutoPauseEnabled(false)
            if let resume = await arbiter.pendingResumeTask { await resume.value }
        }
        await firstLook(scheduler, arbiter, clock: clock)
        await TestWait.until { mute.unmuteCount == 1 }
    }

    @Test("a mute made just as the Mac falls asleep is lifted at once: no pause is held while it sleeps")
    func muteAsMacSleepsLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                         mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        mute.whileMuting = { await arbiter.setAsleep(true) }
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 1)
        #expect(mutedInstead.value.isEmpty) // never said Muted
        #expect(await arbiter.pausedByUs == false)
    }

    @Test("a mute made just as AntiDot mode is turned on is lifted at once, the player paused for real: no tap stays in AntiDot mode")
    func muteAsAntiDotOnLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), taps = Locked(true)
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published, tapsAllowed: taps,
                                         scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        // As the pipeline does: the flag first, then the arbiter told.
        mute.whileMuting = {
            taps.value = false
            await arbiter.setTapsAllowed(false)
        }
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        #expect(mute.unmuteCount == 1)
        #expect(await player.pauseCallCount == 2) // paused for real
        #expect(await arbiter.mutedInstead == false)
        #expect(published.state == .pausedByMonitor) // still AutoHush's pause
        #expect(scheduler.scheduledDelays.last != PlaybackArbiter.silentRecheckInterval) // not watched in AntiDot mode
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a mute made just as AntiDot mode is turned on and the other app stops: paused for real, unmuted, then resumed")
    func muteAsAntiDotOnAndAppsStopResumed() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), taps = Locked(true)
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published, tapsAllowed: taps,
                                         scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        mute.whileMuting = {
            taps.value = false
            await arbiter.setTapsAllowed(false)
            await arbiter.sourceChanged("org.videolan.vlc", playing: false)
            if let resume = await arbiter.pendingResumeTask { await resume.value }
        }
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 1)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(published.state == .musicPlaying)
    }

    @Test("muted, a relaunched player whose new process can't be muted plays on, its pause failed")
    func relaunchUnmutable() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        mute.relaunchMuted = false
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(published.state == .pauseFailed)
        #expect(await player.pauseCallCount == 1) // not pressed
    }

    @Test("muted, a look whose measure ends after the monitoring stopped presses nothing")
    func mutedLookAfterShutdown() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        hearing.beforeAnswer = { await arbiter.shutdown() }
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 1)
        #expect(mute.unmuteCount == 1) // by the shutdown
    }

    @Test("muted, a player found paused by the resume (before a look made it a pause) is unmuted before it plays, so its fade-in is heard")
    func mutedFoundPausedUnmutedFirst() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), playsAtUnmute = Locked<[Int]>([])
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        mute.whileUnmuting = { playsAtUnmute.append(await player.playCallCount) }
        await player.setState(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(playsAtUnmute.value == [0])
    }

    @Test("the player started while another app plays is the user's only after input just before: input long before doesn't count")
    func startedLongAfterInputPaused() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), published = LastPublished()
        let inputAsked = Locked<[Date]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      clock: { clock.now }, onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { _ in .heard }, inputToPlayer: { inputAsked.append($0); return false })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        clock.advance(by: 20)
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        #expect(inputAsked.value.last == clock.now.addingTimeInterval(-PlaybackArbiter.playInputWindow))
        await TestWait.until { await player.pauseCallCount == 1 }
    }

    @Test("a player whose pause is a mute of its own (a web page during an ad) isn't watched or muted again: left to its mute")
    func ownMuteLeftAlone() async {
        let mock = MockMusicPlayer(), mute = FakeMute(), scheduler = ManualDebounceScheduler()
        let player = MockMutingMusicPlayer(mock)
        await player.setMutedForPause(true)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      hearsPlayer: { _ in .heard }, inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await mock.pauseCallCount == 1 }
        await arbiter.waitForPause()
        #expect(!scheduler.scheduledDelays.contains(PlaybackArbiter.restartWatchDelay)) // not watched
        await arbiter.handlePlayerHeard() // heard through its own mute
        #expect(mute.muteCount == 0)
        // Said to play while its page is muted (the ad plays on): the pause stands.
        await mock.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        #expect(await arbiter.pausedByUs)
    }

    @Test("a player whose pause is always a mute (an app added as Mute It Instead) isn't watched or muted again")
    func muteOnlyAppLeftAlone() async {
        let player = MockMusicPlayer(pausesByMuting: true), mute = FakeMute(), scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      hearsPlayer: { _ in .heard }, inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitForPause()
        #expect(!scheduler.scheduledDelays.contains(PlaybackArbiter.restartWatchDelay))
        await arbiter.handlePlayerHeard()
        #expect(mute.muteCount == 0)
        #expect(await arbiter.pausedByUs) // heard through its mute: still AutoHush's pause
    }

    @Test("muted, a player the user paused just before (their key or click in it) is theirs: unmuted, not resumed")
    func mutedUserPauseTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), userPlayed = Locked(false), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                        published: published, scheduler: scheduler)
        userPlayed.value = true
        hearing.now = .silent
        await player.setState(.paused)
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 1)
        #expect(published.state == .musicIdle)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("muted, the Mac falling asleep pauses the player for real before its mute is lifted, so it wakes paused")
    func mutedSleepPausesFirst() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), playsAtUnmute = Locked<[Int]>([]), pausesAtUnmute = Locked<[Int]>([])
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        mute.whileUnmuting = {
            playsAtUnmute.append(await player.playCallCount)
            pausesAtUnmute.append(await player.pauseCallCount)
        }
        await arbiter.setAsleep(true)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(pausesAtUnmute.value == [2]) // paused for real before
        #expect(await player.state == .paused)
    }

    @Test("muted, a player that refuses its real pause as the Mac sleeps or AntiDot mode turns on is unmuted and plays on: Couldn't pause", arguments: [true, false])
    func mutedRealPauseRefused(sleeps: Bool) async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        if sleeps { await arbiter.setAsleep(true) } else { await arbiter.setTapsAllowed(false) }
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(await arbiter.pauseFailure == .playerCommandFailed(.pressFailed))
        if !sleeps { #expect(published.state == .pauseFailed) }
    }
}
