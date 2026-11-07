import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    /// Muted in place of the pause, its pause kept once the apps stop
    /// (Resume playback off) and its real pause refused: a kept mute (K1-2).
    /// Its sound is unknown from then, as the monitor answers with no app
    /// playing: the player is measured only beside one (F-1).
    func keptMute(_ player: MockMusicPlayer, clock: ManualClock, hearing: Hearing = Hearing(.heard), mute: FakeMute,
                  published: LastPublished, mutedInstead: Locked<[Bool]>? = nil,
                  scheduler: ManualDebounceScheduler) async -> PlaybackArbiter {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                               configuration: configuration, mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        hearing.now = .unknown // measured no more once no app plays
        await arbiter.sourceChanged("org.example.viewer", playing: false) // its resume keeps the pause instead
        await arbiter.waitUntilIdle()
        #expect(await arbiter.keptMuteStands)
        return arbiter
    }

    /// The next look at a kept mute, once its pause can be pressed again:
    /// as late as the arbiter asked for it (F-5).
    func nextKeptMuteLook(_ scheduler: ManualDebounceScheduler, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: scheduler.scheduledDelays.last ?? PlaybackArbiter.silentRecheckInterval)
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()
    }

    enum KeptMuteResumed: CaseIterable, Sendable {
        case autoPauseOff, checkEnds
    }

    @Test("a kept mute is still shown as Muted, with Unmute, after a resume that keeps it again: Auto-Pause or Turn off for, or Add an App's check ending (C-1)",
          arguments: KeptMuteResumed.allCases)
    func keptMuteShownAfterResume(_ resumed: KeptMuteResumed) async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await keptMute(player, clock: clock, mute: mute, published: published, mutedInstead: mutedInstead,
                                     scheduler: scheduler)
        switch resumed {
        case .autoPauseOff:
            await arbiter.setAutoPauseEnabled(false)
        case .checkEnds:
            await arbiter.holdResumes(true)
            await arbiter.holdResumes(false)
        }
        await arbiter.waitUntilIdle()
        #expect(published.state == .pausedByMonitor) // no publish of the test's own
        #expect(mutedInstead.value.last == true)
        #expect(mute.unmuteCount == 0)
        #expect(await arbiter.pausedByUs)
        #expect(await player.playCallCount == 0)
    }

    @Test("a kept mute stays when the player doesn't answer as its report is checked: the report may be stale (C-3)")
    func keptMuteIgnoresUncheckedReport() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await keptMute(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        await player.setState(.unknown) // no answer
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 0)
        #expect(await arbiter.pausedByUs)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("muted, the output going away while an app plays, its real pause refused: once the apps stop it stays muted, shown with Unmute, never resumed on the next output (D1)")
    func disconnectKeptMuteOutlastsApps() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true // Resume playback on
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.handleOutputDisconnected()
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 0)
        #expect(await arbiter.pausedByUs)
        #expect(await player.playCallCount == 0)
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value.last == true)

        // Another app plays and stops: still kept, not resumed.
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 0)
        #expect(await arbiter.keptMuteStands)
        #expect(await player.playCallCount == 0)
    }

    @Test("muted, the output going away while an app plays: if its real pause takes as the apps stop, it's unmuted and left paused, the user's (D1)")
    func disconnectKeptMutePausedAsAppsStop() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true // Resume playback on
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.handleOutputDisconnected() // refused: kept muted
        await player.setFailPause(nil) // the ad is over: it can be paused now
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(await player.state == .paused)
        #expect(await player.playCallCount == 0)
        #expect(published.state != .pausedByMonitor)
    }

    @Test("muted, the output going away while an app plays and its real pause refused: once it's silent beside the app (its pause took), it's unmuted and left paused, never resumed (D1, C-4)")
    func disconnectKeptMuteSilentBesideApp() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true // Resume playback on
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.handleOutputDisconnected() // refused: kept muted
        #expect(await arbiter.mute.outlastsApps)
        hearing.now = .silent // it paused (the ad is over), measured beside the app
        await nextLook(scheduler, arbiter, clock: clock)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicIdle)

        hearing.now = .unknown
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("muted while Add an App's check holds resumes, the apps stopping: nothing is pressed while it's held; the check ending keeps its pause (Resume playback off), its refusal shown as Muted and its real pause tried again from then (C-1, C-4)")
    func keptMuteAsCheckEnds() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                               configuration: configuration, mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.holdResumes(true)
        hearing.now = .unknown // measured no more once no app plays
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        let pauses = await player.pauseCallCount, looks = scheduler.scheduledDelays.count
        await nextLook(scheduler, arbiter, clock: clock) // held, no app playing: not looked at
        #expect(await player.pauseCallCount == pauses)
        #expect(scheduler.scheduledDelays.count == looks) // nor looked at again

        await arbiter.holdResumes(false) // the check ends: its pause kept, refused
        await arbiter.waitUntilIdle()
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value.last == true)
        #expect(await player.pauseCallCount == pauses + 1)
        await nextLook(scheduler, arbiter, clock: clock) // a kept mute: looked at, its pause pressed
        #expect(await player.pauseCallCount == pauses + 2)
        #expect(mute.unmuteCount == 0)
    }

    @Test("a kept mute, not measured with no app playing, has its pause pressed quietly every 2 s (less often while it fails), judged by its own state: once paused, it's unmuted and left paused, never resumed (C-4, F-1)")
    func keptMuteRetriesRealPause() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await keptMute(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                     mutedInstead: mutedInstead, scheduler: scheduler)
        let before = await player.pauseCallCount
        await nextLook(scheduler, arbiter, clock: clock) // not measured, it says it plays: pressed, refused (1)
        #expect(await player.pauseCallCount == before + 1)
        #expect(await player.quietPauses == 1) // by a way that shows nothing
        await nextLook(scheduler, arbiter, clock: clock) // 1 s since: waits 2 s
        #expect(await player.pauseCallCount == before + 1)
        await player.setFailPause(nil) // it can be paused now (the ad is over)
        await nextLook(scheduler, arbiter, clock: clock) // 2 s: pressed, paused
        #expect(await player.pauseCallCount == before + 2)
        #expect(await player.quietPauses == 2)
        #expect(mute.unmuteCount == 0) // until its state says so
        await nextLook(scheduler, arbiter, clock: clock) // 1 s since: not asked yet
        #expect(mute.unmuteCount == 0)

        await nextLook(scheduler, arbiter, clock: clock) // 2 s: it says it's paused
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await player.pauseCallCount == before + 2) // not pressed again
        #expect(hearing.now == .unknown)
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicIdle)
        #expect(mutedInstead.value.last == false)

        // Its pause is the user's: an app playing and stopping doesn't resume it.
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a kept mute found stopped as its pause is due is unmuted and left so, the user's, nothing pressed (F-1)")
    func keptMuteFoundStopped() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await keptMute(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
        let before = await player.pauseCallCount
        await player.setState(.stopped) // with no report of it
        await nextLook(scheduler, arbiter, clock: clock)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await player.pauseCallCount == before)
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicIdle)
    }

    @Test("a kept mute is looked at only as often as its pause can be pressed: every 2 s, less often while it fails, not every second; every second again once an app plays (F-5)")
    func keptMuteLooksBackOff() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await keptMute(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                     scheduler: scheduler)
        let before = await player.pauseCallCount
        await nextLook(scheduler, arbiter, clock: clock) // pressed, refused (1)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.mutedPauseWait(afterFailures: 1))
        await nextKeptMuteLook(scheduler, arbiter, clock: clock) // pressed, refused (2)
        #expect(await player.pauseCallCount == before + 2)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.mutedPauseWait(afterFailures: 2))
        await player.setIgnoredPresses(1) // the next press goes through, but it plays on
        await player.setFailPause(nil)
        await nextKeptMuteLook(scheduler, arbiter, clock: clock) // pressed (3), it plays on
        #expect(await player.pauseCallCount == before + 3)
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.mutedPauseRetry)
        #expect(mute.unmuteCount == 0)

        // An app plays: looked at every second again, as while muted.
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        hearing.now = .heard
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitUntilIdle()
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.silentRecheckInterval)
        #expect(await arbiter.mutedInstead)
    }

    @Test("a player not chosen (held paused after the user chose another) keeps no mute with no app playing: unmuted, its pause over, whether it was kept before or after (D2)",
          arguments: [false, true])
    func unshownKeptMuteEnds(keptFirst: Bool) async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        let arbiter: PlaybackArbiter
        if keptFirst {
            arbiter = await keptMute(player, clock: clock, mute: mute, published: published, scheduler: scheduler)
            await arbiter.setKeptMuteShown(false)
        } else {
            var configuration = AppConfiguration.testing
            configuration.resumesPlayback = false
            arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
            await arbiter.setKeptMuteShown(false)
            await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
            await arbiter.sourceChanged("org.example.viewer", playing: false)
        }
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(await arbiter.leftToUser)
        #expect(published.state != .pausedByMonitor) // the hold ends
        #expect(await player.playCallCount == 0) // it plays already
    }

    @Test("Unmute pressed while a kept pause's real pause is tried leaves no kept mute behind, which would keep later pauses from being resumed")
    func unmuteDuringKeptPauseLeavesNoFlag() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler()
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        // The menu's Unmute lands while the kept pause tries the real one.
        await player.setBeforePause { await arbiter.unmuteInstead() }
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        await player.setBeforePause(nil)
        #expect(await !arbiter.mute.outlastsApps)
        // The flag would keep every later pause from being resumed
        // (`resumeIfStillPending` keeps a pause it marks).
        #expect(await !arbiter.pausedByUs)
    }

    @Test("a kept mute of a player not chosen any more, while an app plays, stays muted until the last app stops, then it's unmuted and its pause over (F-2)")
    func unshownKeptMuteWaitsForApps() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        let arbiter = await keptMute(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                     scheduler: scheduler)
        hearing.now = .heard // measured beside the video
        await arbiter.sourceChanged("org.example.video", playing: true) // still refused: muted on
        await arbiter.waitUntilIdle()
        await arbiter.setKeptMuteShown(false) // another player chosen
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 0) // not heard over the video
        #expect(await arbiter.pausedByUs)
        #expect(published.state == .pausedByMonitor)

        hearing.now = .unknown
        await arbiter.sourceChanged("org.example.video", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state != .pausedByMonitor) // the hold ends
        #expect(await player.playCallCount == 0)
    }

    @Test("a player held paused, muted, whose output goes away while an app plays and which refuses that pause stays muted until the app stops, then it's unmuted and its pause over (F-2, D1)")
    func unshownDisconnectWaitsForApps() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true // Resume playback on
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
        await arbiter.setKeptMuteShown(false) // another player chosen: held
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.handleOutputDisconnected()
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 0) // not heard on the speakers
        #expect(await arbiter.pausedByUs)
        #expect(published.state == .pausedByMonitor)

        hearing.now = .unknown
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state != .pausedByMonitor) // the hold ends
        #expect(await player.playCallCount == 0)
    }

    @Test("AntiDot mode turned on during a kept mute whose real pause now works: unmuted and left paused, the user's, never resumed (F-3)")
    func keptMuteAntiDotPaused() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await keptMute(player, clock: clock, mute: mute, published: published, mutedInstead: mutedInstead,
                                     scheduler: scheduler)
        await player.setFailPause(nil) // the ad is over
        await arbiter.setTapsAllowed(false)
        await arbiter.waitUntilIdle()
        #expect(mute.unmuteCount == 1)
        #expect(await player.state == .paused)
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicIdle)
        #expect(mutedInstead.value.last == false)

        // An app playing and stopping doesn't resume it.
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("Unmute, then a new app's refused pause muting it again, while a kept pause's real pause is tried: the new mute isn't marked kept (F-4)")
    func newMuteDuringKeptPauseNotKept() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), ran = Locked(false)
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        // While the kept pause tries the real one: the menu's Unmute, then a
        // new app whose pause is refused too, so it's muted again.
        await player.setBeforePause {
            guard !ran.value else { return }
            ran.value = true
            await arbiter.unmuteInstead()
            await arbiter.sourceChanged("org.example.other", playing: true)
        }
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        await player.setBeforePause(nil)
        #expect(ran.value)
        #expect(mute.muteCount == 2)
        #expect(await arbiter.mutedInstead) // the new app's mute
        #expect(await arbiter.pausedByUs)
        #expect(await !arbiter.mute.outlastsApps) // not kept: resumed once the apps stop
    }
}
