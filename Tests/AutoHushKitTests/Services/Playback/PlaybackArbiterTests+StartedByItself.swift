import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    @Test("the player starting by itself while another app plays (a TV app's autoplay) is paused, as at the app's start")
    func startedDuringAppsPaused() async {
        let player = MockMusicPlayer(state: .paused), published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { published.set($0) }), hearsPlayer: { _ in .heard },
                                      inputToPlayer: { _ in false })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 0) // nothing to pause yet
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitForPause()
        #expect(published.state == .pausedByMonitor)
    }

    @Test("the player started by the user while another app plays is left playing, until another app starts")
    func startedByUserDuringApps() async {
        let player = MockMusicPlayer(state: .paused), published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { published.set($0) }), hearsPlayer: { _ in .heard },
                                      inputToPlayer: { _ in true })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.handlePlayerHeard()
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 0)
        #expect(published.state == .musicPlaying)

        await arbiter.sourceChanged("com.apple.Safari", playing: true) // another app: paused for it
        await TestWait.until { await player.pauseCallCount == 1 }
    }

    @Test("paused again on its report, the earlier look at the pause is called off, and forgotten once its task ends")
    func calledOffLookForgotten() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        await reportsPlaying(player, arbiter, clock: clock) // heard: muted, watched afresh
        #expect(mute.muteCount == 1)
        let asked = hearing.timesAsked, looked = mute.relaunchLookCount
        await scheduler.completeNext() // the look from before, called off
        await arbiter.waitUntilIdle()
        #expect(hearing.timesAsked == asked)
        #expect(mute.relaunchLookCount == looked) // nor a look while muted
        await TestWait.until { await arbiter.calledOffWatches.isEmpty }
    }

    @Test("a player that says it plays but wasn't heard through the pause (a TV app's trailers, which report nothing) is resumed")
    func unheardPlayingResumed() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, published: published, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock) // measured silent
        hearing.now = .unknown // the app's output closed: nothing measured
        await player.overrideState(.playing) // its open output reads as playing
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for _ in 0..<2 { await scheduler.completeNext() } // the watch, then the resume's wait, if any
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a player reported playing but not heard during the pause, then measured no more, is resumed")
    func reportedUnheardResumed() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, published: published, scheduler: scheduler)
        hearing.now = .silent
        await reportsPlaying(player, arbiter, clock: clock) // a report of playing, not heard
        #expect(published.state == .pausedByMonitor)
        hearing.now = .unknown
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for _ in 0..<2 { await scheduler.completeNext() } // the watch, then the resume's wait, if any
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a look that can't measure the player (the other app's output closed) tells nothing: the pause stands, and it's resumed with the apps")
    func unmeasuredLookStands() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, published: published, scheduler: scheduler)
        hearing.now = .unknown
        await firstLook(scheduler, arbiter, clock: clock)
        await arbiter.handlePlayerHeard()
        #expect(published.state == .pausedByMonitor)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for _ in 0..<2 { await scheduler.completeNext() } // the watch, then the resume's wait, if any
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("heard at a look after it was silent, just after the user played the player, it's theirs")
    func lookedUserPlayedTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let userPlayed = Locked(false), hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                         published: published, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock)
        userPlayed.value = true
        hearing.now = .heard
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 0)
        #expect(published.state == .musicPlaying)
    }

    @Test("never silent since the pause, the player is muted though the user pressed a key (one meant for the other app): nothing of theirs started it")
    func neverSilentInputMuted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, userPlayed: Locked(true), mute: mute,
                                         published: published, scheduler: scheduler)
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("heard again long after the pause, only the user's input of the last moments counts as their play, not one from long before")
    func oldInputNotCounted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), inputAsked = Locked<[Date]>([])
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                         inputAsked: inputAsked, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock)
        clock.advance(by: 20)
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        #expect(inputAsked.value.last == clock.now.addingTimeInterval(-PlaybackArbiter.playInputWindow))
        #expect(mute.muteCount == 1)
    }

    @Test("the player's sound coming out of this Mac again while another app plays (it played elsewhere) is paused")
    func localAgainDuringAppsPaused() async {
        let player = MockMusicPlayer(), published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { published.set($0) }), hearsPlayer: { _ in .heard },
                                      inputToPlayer: { _ in false })
        await arbiter.refreshPlaybackState()
        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        #expect(await player.pauseCallCount == 0) // playing elsewhere: left alone
        await arbiter.handleLocalPlaybackChange(true)
        await TestWait.until { await player.pauseCallCount == 1 }
    }
}
