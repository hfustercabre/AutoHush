import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Heard during the pause, muted in its place

    /// An arbiter whose player another app (VLC, as a sample) paused, heard as
    /// `hearing` says, the user having played it since a moment as `userPlayed` says.
    private func pausedForAnotherApp(_ player: MockMusicPlayer, clock: ManualClock, userPlayed: Locked<Bool> = Locked(false),
                              hearing: Hearing = Hearing(.heard), mute: FakeMute? = FakeMute(), published: LastPublished,
                              configuration: AppConfiguration = .testing, mutedInstead: Locked<[Bool]>? = nil,
                              inputAsked: Locked<[Date]>? = nil, tapsAllowed: Locked<Bool> = Locked(true),
                              scheduler: ManualDebounceScheduler = ManualDebounceScheduler()) async -> PlaybackArbiter {
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler,
                                      clock: { clock.now },
                                      onStatusUpdate: statuses(playback: { published.set($0) }, mutedInstead: { mutedInstead?.append($0) }),
                                      hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { inputAsked?.append($0); return userPlayed.value }, playerMute: mute,
                                      tapsAllowed: { tapsAllowed.value })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitUntilIdle()
        return arbiter
    }

    /// The player says it plays again, a second later.
    private func reportsPlaying(_ player: MockMusicPlayer, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: 1)
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
    }

    /// The first look after the pause, `restartWatchDelay` later.
    private func firstLook(_ scheduler: ManualDebounceScheduler, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: PlaybackArbiter.restartWatchDelay)
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()
    }

    @Test("still heard at the first look after the pause (it didn't take: Apple TV's trailers play on), the player is muted at once until the apps stop, then unmuted, not played")
    func pauseNotTakenMuted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let mutedInstead = Locked<[Bool]>([]), hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let paused = clock.now
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                         mutedInstead: mutedInstead, scheduler: scheduler)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.restartWatchDelay)
        await player.setState(.playing) // the pause didn't take
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 1)
        #expect(await player.pauseCallCount == 1) // not paused again
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value == [true]) // the menu says Muted
        #expect(hearing.since.last == paused.addingTimeInterval(PlaybackArbiter.pauseTail)) // its sound since the pause only

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0) // it plays already: only unmuted
        #expect(published.state == .musicPlaying)
        #expect(mutedInstead.value == [true, false])
    }

    @Test("silent at the first look, the pause stands and is looked at again a second later")
    func silentPauseStands() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(mute.muteCount == 0)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("heard again by itself during the pause (the next trailer), told by the monitor at once, the player is muted, not paused again")
    func heardAgainMuted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock)
        clock.advance(by: 20) // long after the pause: no time limit
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        #expect(mute.muteCount == 1)
        #expect(await player.pauseCallCount == 1)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("heard again after it was silent, just after the user pressed a key or clicked in the player, it's theirs: left playing, not resumed")
    func userPlayedIsTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let userPlayed = Locked(false), hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let inputAsked = Locked<[Date]>([])
        let paused = clock.now
        let arbiter = await pausedForAnotherApp(player, clock: clock, userPlayed: userPlayed, hearing: hearing, mute: mute,
                                         published: published, inputAsked: inputAsked, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock)
        userPlayed.value = true
        hearing.now = .heard
        await arbiter.handlePlayerHeard()
        #expect(inputAsked.value.last == paused) // since the pause, as it's within the window
        #expect(mute.muteCount == 0)
        #expect(published.state == .musicPlaying)
        await arbiter.handlePlayerHeard() // heard again: still theirs
        #expect(await player.pauseCallCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a player said to play during the pause but not heard (a late report, a silent start) is left alone, the pause still AutoHush's")
    func reportedNotHeardStands() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard)
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published)
        hearing.now = .silent
        await reportsPlaying(player, arbiter, clock: clock)
        #expect(mute.muteCount == 0)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("with nothing measured (AntiDot mode), a player said to play during the pause is the user's only after their key or click in it just before; otherwise it's paused again", arguments: [true, false])
    func unmeasuredRestartNeedsInput(userPlayed: Bool) async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard)
        let arbiter = await pausedForAnotherApp(player, clock: clock, userPlayed: Locked(userPlayed), hearing: hearing, published: published)
        hearing.now = .unknown
        await reportsPlaying(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == (userPlayed ? 1 : 2))
        #expect(published.state == (userPlayed ? .musicPlaying : .pausedByMonitor))
        #expect(await arbiter.pausedByUs == !userPlayed)
    }

    @Test("with nothing measured, a player said to play during the pause that refuses its pause again plays on, its pause failed (nothing to mute it by)")
    func unmeasuredRestartRefused() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard)
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: FakeMute(works: false), published: published)
        hearing.now = .unknown
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await reportsPlaying(player, arbiter, clock: clock)
        #expect(published.state == .pauseFailed)
        #expect(await arbiter.pausedByUs == false)
    }

    @Test("measured too briefly since the pause to tell, the player is looked at again once it can be")
    func measuringLooksAgain() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published, scheduler: scheduler)
        hearing.now = .measuring(remaining: 0.3)
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(scheduler.scheduledDelays.last == 0.3)
        #expect(mute.muteCount == 0)
    }

    @Test("a pause the player refuses is a mute instead; one that can't be muted either fails, as the menu says")
    func refusedPauseMuted() async {
        let player = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.pressIgnored))
        let clock = ManualClock(), mute = FakeMute(), published = LastPublished(), mutedInstead = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      clock: { clock.now },
                                      onStatusUpdate: statuses(playback: { published.set($0) }, mutedInstead: { mutedInstead.append($0) }),
                                      hearsPlayer: { _ in .heard }, inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { mute.muteCount == 1 }
        await arbiter.waitForPause()
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value == [true])

        let stubborn = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.pressIgnored)), unmutable = LastPublished()
        let other = PlaybackArbiter(player: stubborn, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                    onStatusUpdate: statuses(playback: { unmutable.set($0) }), hearsPlayer: { _ in .heard },
                                    playerMute: FakeMute(works: false))
        await other.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { unmutable.state == .pauseFailed }
    }

    @Test("a player heard during the pause that can't be muted plays on, its pause failed")
    func unmutablePlaysOn() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, mute: FakeMute(works: false), published: published, scheduler: scheduler)
        await firstLook(scheduler, arbiter, clock: clock)
        #expect(published.state == .pauseFailed)
    }

    /// An arbiter whose player didn't take its pause, so it's muted.
    private func mutedForAnotherApp(_ player: MockMusicPlayer, clock: ManualClock, userPlayed: Locked<Bool> = Locked(false),
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
    private func nextLook(_ scheduler: ManualDebounceScheduler, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
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

    @Test("the player starting by itself while another app plays (Apple TV's autoplay) is paused, as at the app's start")
    func startedDuringAppsPaused() async {
        let player = MockMusicPlayer(state: .paused), published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { published.set($0) }), hearsPlayer: { _ in .heard },
                                      inputToPlayer: { _ in false })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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

    @Test("a player that says it plays but wasn't heard through the pause (Apple TV's trailers, which report nothing) is resumed")
    func unheardPlayingResumed() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await pausedForAnotherApp(player, clock: clock, hearing: hearing, published: published, scheduler: scheduler)
        hearing.now = .silent
        await firstLook(scheduler, arbiter, clock: clock) // measured silent
        hearing.now = .unknown // the app's output closed: nothing measured
        await player.overrideState(.playing) // its open output reads as playing
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 0) // playing elsewhere: left alone
        await arbiter.handleLocalPlaybackChange(true)
        await TestWait.until { await player.pauseCallCount == 1 }
    }

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

    @Test("heard while it says it's paused, as another app plays, the player is muted a moment later, past a pause's tail; when the apps stop it's only unmuted, never played")
    func heardWhileSayingPausedMuted() async {
        let player = MockMusicPlayer(state: .paused), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), hearing = Hearing(.heard)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      clock: { clock.now }, onStatusUpdate: statuses(playback: { published.set($0) }),
                                      hearsPlayer: { await hearing.answer(since: $0) },
                                      inputToPlayer: { _ in false }, playerMute: mute)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        clock.advance(by: PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitForPause()
        await arbiter.waitUntilIdle()
        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock) // only unmuted: that pause is over
        #expect(mute.muteCount == 1 && mute.unmuteCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        // Later, playing: its pause doesn't take, so it's muted in its place.
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.waitUntilIdle()
        clock.advance(by: 10)
        hearing.now = .heard
        let pauses = await player.pauseCallCount
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }
}
