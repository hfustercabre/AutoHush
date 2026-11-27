import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Taking back a pause held by a mute

    /// A player AutoHush paused by a mute of its own: a page muted in place
    /// of its pause (`isMutedForPause`), or an app only ever muted (`pausesByMuting`).
    enum OwnMute: String, CaseIterable, Sendable {
        case page, mutedApp

        func player() async -> any MusicPlayer {
            switch self {
            case .page:
                let page = MockMutingMusicPlayer(MockMusicPlayer(state: .paused))
                await page.setMutedForPause(true)
                return page
            case .mutedApp:
                return MockMusicPlayer(state: .paused, pausesByMuting: true)
            }
        }
    }

    @Test("a page muted in place of its pause is taken over with its mute, which this arbiter lifts as it shuts down")
    func takenOverWithPagesMute() async {
        let page = MockMutingMusicPlayer(MockMusicPlayer(state: .paused))
        await page.setMutedForPause(true)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause())
        #expect(await arbiter.heldByMute)
        await arbiter.shutdown()
        #expect(await page.releasedMutes == 1)
    }

    @Test("a pause taken over that is the player's own mute is left to it when the player is heard through it as the apps play",
          arguments: OwnMute.allCases)
    func takenOverOwnMuteHeard(_ kind: OwnMute) async {
        let player = await kind.player()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause())
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.handlePlayerHeard() // the new monitor hears it through its mute
        #expect(await arbiter.pausedByUs)
    }

    @Test("handing over to a new monitoring of the same player, it leaves the player's own mute to that one, and lifts its own tap's")
    func handingOverLeavesOwnMute() async {
        let page = MockMutingMusicPlayer(MockMusicPlayer(state: .paused))
        await page.setMutedForPause(true)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause())
        await arbiter.shutdown(handingOver: true)
        #expect(await page.releasedMutes == 0)

        let mute = FakeMute()
        let tapped = PlaybackArbiter(player: MockMusicPlayer(state: .playing), configuration: .testing,
                                     debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        #expect(await tapped.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        await tapped.shutdown(handingOver: true)
        #expect(mute.unmuteCount == 1)
    }

    @Test("found playing as the monitoring before held its pause by its tap: muted again at once by this one's, in place of the pause, unmuted (not played) at the resume")
    func mutedAgainByTap() async {
        let player = MockMusicPlayer(state: .playing)
        let mute = FakeMute(), scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler, playerMute: mute)
        #expect(await arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        #expect(mute.muteCount == 1)
        #expect(await arbiter.pausedByUs)
        #expect(await arbiter.mutedInstead)
        #expect(await player.pauseCallCount == 0)

        await scheduler.completeNext() // no app found by then
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("found paused as the monitoring before held its pause by its tap (paused under it): taken over as a pause, with no new mute")
    func pausedUnderTapTakenOver() async {
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .paused), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        #expect(await arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        #expect(mute.muteCount == 0)
        #expect(await !arbiter.mutedInstead)
    }

    @Test("found paused or stopped as the monitoring before held its pause by its tap made while it said so, heard: muted again all the same, unmuted (not played) at the resume (N1 of 11-27)",
          arguments: [PlayerState.paused, .stopped])
    func quietTapMutedAgain(_ state: PlayerState) async {
        let player = MockMusicPlayer(state: state)
        let mute = FakeMute(), scheduler = ManualDebounceScheduler(), whileQuiet = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: { if case .mutedInstead(true, let quiet) = $0 { whileQuiet.append(quiet) } },
                                      playerMute: mute)
        #expect(await arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: true)))
        #expect(mute.muteCount == 1)
        #expect(await arbiter.mutedInstead)
        #expect(whileQuiet.value.last == true) // so a later take-back mutes it again so too

        await scheduler.completeNext() // no app found by then
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("not running as the monitoring before held its pause by its tap made while it said it's paused: nothing muted, nothing taken over")
    func quietTapNotRunning() async {
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .notRunning), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        #expect(await !arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: true)))
        #expect(mute.muteCount == 0)
    }

    @Test("its tap can't mute it (AntiDot mode, no Audio Recording): not taken over, and the apps, once counted, pause it as any")
    func tapRefused() async {
        let mute = FakeMute(works: false)
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .playing), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        #expect(await !arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        #expect(await !arbiter.pausedByUs)
        #expect(await !arbiter.mutedInstead)
    }

    @Test("stopped, or the Mac asleep, while its tap is made: the mute is lifted again, and nothing is taken over", arguments: [false, true])
    func changedWhileMuting(asleep: Bool) async {
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .playing), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        mute.whileMuting = { [arbiter] in
            if asleep { await arbiter.setAsleep(true, change: 1) } else { await arbiter.shutdown() }
        }
        #expect(await !arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        #expect(mute.muteCount == 1 && mute.unmuteCount == 1)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("found playing as another object of the app held its pause by its own mute (checked again): this one's quiet pause mutes it again, taken over as its own mute, left to it when heard")
    func mutedAgainByPlayer() async {
        let player = MockMusicPlayer(state: .playing, pausesByMuting: true)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await player.quietPauses == 1)
        #expect(await arbiter.pausedByUs)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.handlePlayerHeard()
        #expect(await arbiter.pausedByUs)
    }

    @Test("not answering as the monitoring before held its pause by its tap: muted again all the same, a tap muting whatever it says (R3 of 11-27)")
    func unansweredMutedAgainByTap() async {
        let player = MockMusicPlayer(state: .playing)
        await player.setUnansweredStateQueries(1)
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      playerMute: mute)
        #expect(await arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        #expect(mute.muteCount == 1)
        #expect(await arbiter.pausedByUs)
        #expect(await arbiter.mutedInstead)
    }

    @Test("found paused or stopped while heard (an ad, its button saying Play) as another object of the app held its pause by its own mute: muted again at once, its pause held by that mute (R1 of 11-27)",
          arguments: [PlayerState.paused, .stopped])
    func adMutedAgain(_ state: PlayerState) async {
        let mock = MockMusicPlayer(state: state)
        await mock.setPlaysAnyway(true)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await mock.muteIfPlayingAnywayCount == 1)
        #expect(await mock.pauseCallCount == 0)
        #expect(await arbiter.pausedByUs)
        #expect(await arbiter.heldByMute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.handlePlayerHeard() // heard through its mute: left to it
        #expect(await arbiter.pausedByUs)
        await arbiter.shutdown()
        #expect(await page.releasedMutes == 1)
    }

    @Test("its quiet pause, pressed as it's taken back, takes for real (the ad over); the site starts again by itself as the apps play: paused again, not left to the user (N2 of 11-27)")
    func pressedPauseStartsAgain() async {
        let mock = MockMusicPlayer(state: .playing)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      inputToPlayer: { _ in false })
        #expect(await arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await mock.pauseCallCount == 1)
        #expect(await !arbiter.heldByMute) // a real pause, its press this arbiter's
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await mock.setState(.playing) // by itself, not by the user
        await arbiter.handlePlayerStateChange(.playing)
        #expect(await arbiter.pausedByUs)
        #expect(await mock.pauseCallCount == 2)
    }

    @Test("found paused and silent as another object of the app held its pause by its own mute: a real pause, taken over with no mute")
    func silentPauseTakenOver() async {
        let mock = MockMusicPlayer(state: .paused)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await arbiter.pausedByUs)
        #expect(await !arbiter.heldByMute)
    }

    @Test("stopped, or the Mac asleep, while an ad's page is muted again: its mute is lifted, and nothing is taken over",
          arguments: [false, true])
    func changedWhileAdMuted(asleep: Bool) async {
        let mock = MockMusicPlayer(state: .paused)
        await mock.setPlaysAnyway(true)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        await page.setBeforeMute { [arbiter] in
            if asleep { await arbiter.setAsleep(true, change: 1) } else { await arbiter.shutdown() }
        }
        #expect(await !arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await page.releasedMutes == 1)
        #expect(await mock.playCallCount == 0)
        #expect(await !arbiter.pausedByUs)
    }

    /// How a quiet pause that muted the page ends with no pause held.
    enum MutedWithoutPause: String, CaseIterable, Sendable {
        /// Another sign (a script's) says it still plays over its page's mute.
        case readsPlaying
        /// It doesn't answer once pressed (Accessibility lost meanwhile).
        case unanswered
        /// The Mac goes to sleep as it's pressed, and it reads as playing.
        case asleep
    }

    @Test("its quiet pause muted the page, but no pause is held (it reads as playing, doesn't answer, or the Mac slept): that mute is lifted again, nothing played (R4 of 11-27)",
          arguments: MutedWithoutPause.allCases)
    func pageMuteLeftWithoutPause(_ exit: MutedWithoutPause) async {
        let mock = MockMusicPlayer(state: .playing)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        if exit != .unanswered { await mock.setIgnoredPresses(1) }
        await mock.setBeforePause { [page, mock, arbiter] in
            await page.setMutedForPause(true)
            switch exit {
            case .readsPlaying: break
            case .unanswered: await mock.setUnansweredStateQueries(1)
            case .asleep: await arbiter.setAsleep(true, change: 1)
            }
        }
        #expect(await !arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await page.releasedMutes == 1)
        #expect(await mock.playCallCount == 0)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("its own mute refused: not taken over")
    func ownMuteRefused() async {
        let player = MockMusicPlayer(state: .playing, pausesByMuting: true,
                                     failPauseWith: MusicPlayerError.playerCommandFailed(.muteUnavailable))
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        #expect(await !arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await !arbiter.pausedByUs)
    }

    @Test("stopped, or the Mac asleep, while its own mute is made: played again (unmuted), as nobody would resume it, and nothing is taken over",
          arguments: [false, true])
    func changedWhileOwnMute(asleep: Bool) async {
        let player = MockMusicPlayer(state: .playing, pausesByMuting: true)
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        await player.setBeforePause { [arbiter] in
            if asleep { await arbiter.setAsleep(true, change: 1) } else { await arbiter.shutdown() }
        }
        #expect(await !arbiter.takeOverPause(mutedBefore: .byPlayer))
        #expect(await player.playCallCount == 1)
        #expect(await player.state == .playing)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("found playing with no mute before: nothing to take over, nothing pressed nor muted")
    func playingWithoutMute() async {
        let player = MockMusicPlayer(state: .playing)
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(), playerMute: mute)
        #expect(await !arbiter.takeOverPause())
        #expect(mute.muteCount == 0)
        #expect(await player.pauseCallCount == 0)
    }

    @Test("stopped while it's asked whether its pause is its own mute: not taken over, and a pause it didn't press isn't played")
    func stoppedWhileAskedOwnMute() async {
        let mock = MockMusicPlayer(state: .paused)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        await page.setBeforeMutedForPause { [arbiter] in await arbiter.shutdown() }
        #expect(await !arbiter.takeOverPause())
        #expect(await mock.playCallCount == 0)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("the Mac going to sleep while it's asked whether its pause is its own mute: forgotten, as any pause then; one pressed just now is played again",
          arguments: [false, true])
    func asleepWhileAskedOwnMute(pressed: Bool) async {
        let mock = MockMusicPlayer(state: pressed ? .playing : .paused)
        let page = MockMutingMusicPlayer(mock)
        let arbiter = PlaybackArbiter(player: page, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        await page.setBeforeMutedForPause { [arbiter] in await arbiter.setAsleep(true, change: 1) }
        #expect(await !arbiter.takeOverPause(mutedBefore: pressed ? .byPlayer : nil))
        #expect(await !arbiter.pausedByUs)
        #expect(await mock.playCallCount == (pressed ? 1 : 0))
    }

    @Test("muted again by its tap, with Resume playback off and no app found: kept muted, its pause still pressed and the player looked at, as any mute in place of a pause")
    func mutedAgainThenKept() async {
        let player = MockMusicPlayer(state: .playing, failPauseWith: MusicPlayerError.playerCommandFailed(.pressIgnored))
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let mute = FakeMute(), scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler, playerMute: mute)
        #expect(await arbiter.takeOverPause(mutedBefore: .byTap(whileQuiet: false)))
        await scheduler.completeNext() // no app found: its pause kept, its real pause refused
        await TestWait.until { scheduler.scheduledDelays.count == 2 } // its look
        await scheduler.completeNext()
        await TestWait.until { mute.relaunchLookCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.quietPauses == 1)
        #expect(mute.unmuteCount == 0)
        #expect(await arbiter.pausedByUs)
    }
}
