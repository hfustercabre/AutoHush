import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    @Test("heard while it says it's paused, as another app plays, the player is muted a moment later, past a pause's tail; when the apps stop it's only unmuted, never played")
    func heardWhileSayingPausedMuted() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), hearing = Hearing(.heard)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      clock: { clock.now }, onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        #expect(mute.muteCount == 0) // heard just now: looked at again first
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval)
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitForPause()
        await arbiter.waitUntilIdle()
        #expect(mute.muteCount == 1)
        #expect(await player.pauseCallCount == 0) // it says it's paused: nothing pressed for that
        #expect(published.state == .pausedByMonitor)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("heard just as it says it's paused (its pause's tail), then not, the player isn't muted")
    func heardTailWhileSayingPausedNotMuted() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), mute = FakeMute()
        let scheduler = ManualDebounceScheduler(), hearing = Hearing(.heard)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      clock: { clock.now }, hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        hearing.now = .silent
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitForPause()
        await arbiter.waitUntilIdle()
        #expect(mute.muteCount == 0)
        #expect(await arbiter.pausedByUs == false)
    }

    @Test("muted while it said it's paused, the player going silent is only unmuted: no pause of AutoHush's to resume")
    func mutedWhileSayingPausedSilentUnmuted() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), hearing = Hearing(.heard)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      clock: { clock.now }, onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitForPause()
        await arbiter.waitUntilIdle()
        #expect(mute.muteCount == 1)
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 1)
        #expect(await arbiter.pausedByUs == false)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a mute made while it said it's paused counts for that pause only: muted in place of a later pause, its silence is that pause, still muted")
    func mutedWhileSayingPausedForgotten() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), hearing = Hearing(.heard)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      clock: { clock.now }, onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitForPause()
        await arbiter.waitUntilIdle()
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock) // only unmuted: that pause is over
        #expect(mute.muteCount == 1 && mute.unmuteCount == 1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()

        // Later, playing: its pause doesn't take, so it's muted in its place.
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.waitUntilIdle()
        clock.advance(by: 10)
        hearing.now = .heard
        let pauses = await player.pauseCallCount
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { await player.pauseCallCount == pauses + 1 }
        await arbiter.waitUntilIdle()
        await player.setState(.playing) // its pause didn't take
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 2)
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 1) // kept until it plays again
        #expect(await arbiter.pausedByUs)
    }

    @Test("an app that can only be muted, said to play during the pause (the menu's Unmute), is the user's: left playing, not muted again")
    func muteOnlyAppUnmutedIsTheirs() async {
        let player = MockMusicPlayer(pausesByMuting: true), mute = FakeMute(), published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { _ in .heard }, inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitForPause()
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicPlaying)
        #expect(mute.muteCount == 0)
    }

    @Test("muted in place of the pause, the menu's Unmute lifts the mute: the user's, not paused or muted again while the apps play")
    func unmuteInsteadIsTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await arbiter.unmuteInstead()
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicPlaying)
        await arbiter.handlePlayerHeard() // heard as it plays: theirs
        await arbiter.waitUntilIdle()
        #expect(mute.muteCount == 1)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("muted, AntiDot mode turned on pauses the player for real and lifts the mute at once; still AutoHush's pause, resumed with the apps")
    func mutedAntiDotPausesAndUnmutes() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                        mutedInstead: mutedInstead, scheduler: scheduler)
        await arbiter.setTapsAllowed(false)
        #expect(await player.pauseCallCount == 2)
        #expect(mute.unmuteCount == 1)
        #expect(mutedInstead.value == [true, false])
        #expect(published.state == .pausedByMonitor)
        await arbiter.setTapsAllowed(true) // measuring again: nothing to do
        #expect(mute.unmuteCount == 1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }
}
