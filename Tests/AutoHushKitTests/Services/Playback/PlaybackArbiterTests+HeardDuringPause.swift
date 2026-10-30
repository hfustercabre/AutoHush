import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Heard during the pause, muted in its place

    /// An arbiter whose player another app (VLC, as a sample) paused, heard as
    /// `hearing` says, the user having played it since a moment as `userPlayed` says.
    func pausedForAnotherApp(_ player: MockMusicPlayer, clock: ManualClock, userPlayed: Locked<Bool> = Locked(false),
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
    func reportsPlaying(_ player: MockMusicPlayer, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: 1)
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
    }

    /// The first look after the pause, `restartWatchDelay` later.
    func firstLook(_ scheduler: ManualDebounceScheduler, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
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
}
