import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    /// An arbiter whose player didn't take its pause, so it's muted.
    func mutedForAnotherApp(_ player: MockMusicPlayer, clock: ManualClock, userPlayed: Locked<Bool> = Locked(false),
                            hearing: Hearing = Hearing(.heard), mute: FakeMute, published: LastPublished,
                            configuration: AppConfiguration = .testing, mutedInstead: Locked<[Bool]>? = nil,
                            scheduler: ManualDebounceScheduler) async -> PlaybackArbiter {
        let arbiter = await pausedForAnotherApp(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                         published: published, configuration: configuration, mutedInstead: mutedInstead,
                                         scheduler: scheduler)
        await player.setState(.playing) // its pause didn't take
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        return arbiter
    }

    /// The next look while muted, a second later.
    func nextLook(_ scheduler: ManualDebounceScheduler, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()
    }

    @Test("muted and still heard, the player's pause is pressed; silent since, it's then AutoHush's pause, still muted, unmuted as it's resumed with the apps")
    func mutedThenPaused() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        await nextLook(scheduler, arbiter, clock: clock) // still heard: its pause pressed
        #expect(await player.pauseCallCount == 2)
        #expect(mute.unmuteCount == 0)
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock) // silent since: paused, the mute kept
        #expect(mute.unmuteCount == 0)
        #expect(published.state == .pausedByMonitor)
        #expect(mute.relaunchLookCount == 2) // a relaunched player muted again at each look

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        #expect(mute.unmuteCount == 1)
    }

    @Test("muted, a pause pressed that doesn't take (still heard: the ad goes on) leaves it muted, pressed again every 2 seconds")
    func mutedPauseNotTaken() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        await nextLook(scheduler, arbiter, clock: clock) // pressed
        await player.setState(.playing) // the ad plays on
        await nextLook(scheduler, arbiter, clock: clock) // still heard, a second later: not yet
        #expect(await player.pauseCallCount == 2)
        await nextLook(scheduler, arbiter, clock: clock) // 2 seconds since: pressed again
        #expect(mute.unmuteCount == 0)
        #expect(await player.pauseCallCount == 3)
    }

    @Test("muted, a pause whose press keeps failing is tried less often each time, not every second")
    func mutedPauseFailingBacksOff() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        let before = await player.pauseCallCount
        await nextLook(scheduler, arbiter, clock: clock) // pressed: failed (1)
        #expect(await player.pauseCallCount == before + 1)
        await nextLook(scheduler, arbiter, clock: clock) // 1 s since: waits 2 s
        #expect(await player.pauseCallCount == before + 1)
        await nextLook(scheduler, arbiter, clock: clock) // 2 s: pressed, failed (2)
        #expect(await player.pauseCallCount == before + 2)
        for _ in 0..<3 { await nextLook(scheduler, arbiter, clock: clock) } // 3 s since: waits 4 s
        #expect(await player.pauseCallCount == before + 2)
        await nextLook(scheduler, arbiter, clock: clock) // 4 s: pressed, failed (3)
        #expect(await player.pauseCallCount == before + 3)
        #expect(PlaybackArbiter.mutedPauseWait(afterFailures: 10) == 60)

        await player.setFailPause(nil) // it can be paused again: pressed at the next wait's end
        for _ in 0..<8 { await nextLook(scheduler, arbiter, clock: clock) }
        #expect(await player.pauseCallCount == before + 4)
        #expect(mute.unmuteCount == 0)

        // A press that went through starts the count again: failing anew,
        // it waits 2 s, not the 16 s of a fourth failure in a row.
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        for _ in 0..<2 { await nextLook(scheduler, arbiter, clock: clock) } // 2 s since the press: failed (1)
        #expect(await player.pauseCallCount == before + 5)
        for _ in 0..<2 { await nextLook(scheduler, arbiter, clock: clock) } // 2 s: pressed again
        #expect(await player.pauseCallCount == before + 6)
    }

    @Test("muted, a player that doesn't state itself (Apple TV's trailers) is pressed too: its sound tells")
    func mutedNoStatePressed() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await player.setStatesItself(false)
        await player.overrideState(.unknown)
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 2)
    }

    @Test("muted, a player silent since the mute (it paused itself: Apple TV's trailers in a hidden window) is AutoHush's pause unpressed, the menu no longer saying Muted, unmuted as it's resumed with the apps")
    func mutedSilentByItselfPaused() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let muted = clock.now.addingTimeInterval(PlaybackArbiter.restartWatchDelay)
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                        mutedInstead: mutedInstead, scheduler: scheduler)
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(hearing.since.last == muted.addingTimeInterval(PlaybackArbiter.pauseTail)) // its sound since the mute
        #expect(mute.unmuteCount == 0) // kept until it plays again
        #expect(mutedInstead.value == [true, false]) // the menu says Paused again
        #expect(await player.pauseCallCount == 1) // not pressed
        #expect(published.state == .pausedByMonitor)
        await player.setState(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        #expect(mute.unmuteCount == 1)
    }

    /// An arbiter whose player was muted, then went silent: paused, still muted.
    private func pausedMutedForVLC(_ player: MockMusicPlayer, clock: ManualClock, userPlayed: Locked<Bool> = Locked(false),
                                   hearing: Hearing, mute: FakeMute, published: LastPublished,
                                   configuration: AppConfiguration = .testing, mutedInstead: Locked<[Bool]>? = nil,
                                   scheduler: ManualDebounceScheduler) async -> PlaybackArbiter {
        let arbiter = await mutedForAnotherApp(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                        published: published, configuration: configuration, mutedInstead: mutedInstead,
                                        scheduler: scheduler)
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock)
        await player.setState(.paused)
        #expect(mute.unmuteCount == 0)
        return arbiter
    }

    @Test("paused with its mute kept, a player that starts again by itself (the next trailer) is never heard: Muted again, nothing muted twice")
    func keptMuteRestartMutedAgain() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await pausedMutedForVLC(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                              mutedInstead: mutedInstead, scheduler: scheduler)
        let looked = mute.relaunchLookCount
        clock.advance(by: 5)
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        #expect(mute.muteCount == 1)
        #expect(mute.unmuteCount == 0)
        #expect(mute.relaunchLookCount == looked + 1) // a relaunched process muted, if any
        #expect(mutedInstead.value == [true, false, true])
        #expect(published.state == .pausedByMonitor)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
    }

    @Test("paused with its mute kept, the user playing it again unmutes it: theirs")
    func keptMuteUserPlayUnmuted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let userPlayed = Locked(false), hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedMutedForVLC(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                              published: published, scheduler: scheduler)
        userPlayed.value = true
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(published.state == .musicPlaying)
    }

    @Test("paused with its mute kept and Resume playback off, the apps stopping lift the mute; it stays paused")
    func keptMuteLiftedWithoutResume() async {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedMutedForVLC(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                              configuration: configuration, scheduler: scheduler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }

    @Test("paused with its mute kept, the mute is lifted as the monitoring stops")
    func keptMuteLiftedAtShutdown() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedMutedForVLC(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                              scheduler: scheduler)
        await arbiter.shutdown()
        #expect(mute.unmuteCount == 1)
    }

    @Test("muted, and unmuted from the menu while a look measures it: the look then presses nothing and keeps nothing, the player the user's")
    func unmutedDuringMutedLook() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        let pausesBefore = await player.pauseCallCount
        hearing.beforeAnswer = { await arbiter.unmuteInstead() }
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(await player.pauseCallCount == pausesBefore) // its pause not pressed after the Unmute
        #expect(mute.unmuteCount == 1)
        #expect(published.state != .pausedByMonitor)
    }

    @Test("muted and still heard, the user's key press or click in the player changes nothing: it plays already, so it stays muted")
    func mutedUserInputKeepsMute() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let userPlayed = Locked(false), scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, userPlayed: userPlayed, mute: mute, published: published, scheduler: scheduler)
        userPlayed.value = true
        await nextLook(scheduler, arbiter, clock: clock)
        #expect(mute.unmuteCount == 0)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("while the resume waits (no other app plays), a player reported playing isn't judged the user's: paused again meanwhile, it's resumed")
    func reportDuringResumeWaitNotTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: nil, published: published, scheduler: scheduler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await reportsPlaying(player, arbiter, clock: clock)
        await player.setState(.paused)
        await arbiter.handlePlayerStateChange(.paused)
        for _ in 0..<2 { await scheduler.completeNext() } // the watch, then the resume's wait, if any
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("muted, a player reported playing is still AutoHush's: the mute stays until the apps stop")
    func mutedPlayingReportKeepsMute() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await arbiter.handlePlayerStateChange(.playing)
        #expect(mute.unmuteCount == 0)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("a mute in place of the pause is lifted as the monitoring stops, never left on")
    func muteLiftedAtShutdown() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await arbiter.shutdown()
        #expect(mute.unmuteCount == 1)
    }

    @Test("a mute made as the monitoring stops is lifted at once")
    func muteDuringShutdownLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        mute.whileMuting = { await arbiter.shutdown() }
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        #expect(mute.unmuteCount == 1)
    }

    @Test("with Resume playback off, a player muted in place of the pause is paused for real, then unmuted, as the apps stop")
    func mutedKeptPausedWithoutResume() async {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                        configuration: configuration, scheduler: scheduler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await player.pauseCallCount == 2) // and once more for real
        #expect(await player.state == .paused)
    }
}
