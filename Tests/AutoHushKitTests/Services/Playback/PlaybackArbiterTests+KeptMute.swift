import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    /// Muted in place of the pause, its pause kept once the apps stop
    /// (Resume playback off) and its real pause refused: a kept mute (K1-2).
    func keptMute(_ player: MockMusicPlayer, clock: ManualClock, hearing: Hearing = Hearing(.heard), mute: FakeMute,
                  published: LastPublished, mutedInstead: Locked<[Bool]>? = nil,
                  scheduler: ManualDebounceScheduler) async -> PlaybackArbiter {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                               configuration: configuration, mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.sourceChanged("org.example.viewer", playing: false) // its resume keeps the pause instead
        await arbiter.waitUntilIdle()
        #expect(await arbiter.keptMuteStands)
        return arbiter
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

    @Test("muted while Add an App's check holds resumes, the apps stopping: nothing is pressed while it's held; the check ending keeps its pause (Resume playback off), its refusal shown as Muted and its real pause tried again from then (C-1, C-4)")
    func keptMuteAsCheckEnds() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let arbiter = await mutedForAnotherApp(player, clock: clock, mute: mute, published: published,
                                               configuration: configuration, mutedInstead: mutedInstead, scheduler: scheduler)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await arbiter.holdResumes(true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        let pauses = await player.pauseCallCount
        await nextLook(scheduler, arbiter, clock: clock) // held, no app playing: not looked at
        #expect(await player.pauseCallCount == pauses)

        await arbiter.holdResumes(false) // the check ends: its pause kept, refused
        await arbiter.waitUntilIdle()
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value.last == true)
        #expect(await player.pauseCallCount == pauses + 1)
        await nextLook(scheduler, arbiter, clock: clock) // a kept mute: looked at, its pause pressed
        #expect(await player.pauseCallCount == pauses + 2)
        #expect(mute.unmuteCount == 0)
    }

    @Test("a kept mute keeps trying its real pause with no app playing, as often as while muted; once paused, it's unmuted and left paused, never resumed (C-4)")
    func keptMuteRetriesRealPause() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(.heard), scheduler = ManualDebounceScheduler(), mutedInstead = Locked<[Bool]>([])
        let arbiter = await keptMute(player, clock: clock, hearing: hearing, mute: mute, published: published,
                                     mutedInstead: mutedInstead, scheduler: scheduler)
        let before = await player.pauseCallCount
        await nextLook(scheduler, arbiter, clock: clock) // heard: pressed, refused (1)
        #expect(await player.pauseCallCount == before + 1)
        await nextLook(scheduler, arbiter, clock: clock) // 1 s since: waits 2 s
        #expect(await player.pauseCallCount == before + 1)
        await player.setFailPause(nil) // it can be paused now (the ad is over)
        await nextLook(scheduler, arbiter, clock: clock) // 2 s: pressed, paused
        #expect(await player.pauseCallCount == before + 2)
        #expect(mute.unmuteCount == 0) // until it's silent

        hearing.now = .silent
        await nextLook(scheduler, arbiter, clock: clock)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await arbiter.pausedByUs == false)
        #expect(published.state == .musicIdle)
        #expect(mutedInstead.value.last == false)

        // Its pause is the user's: an app playing and stopping doesn't resume it.
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
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
}
