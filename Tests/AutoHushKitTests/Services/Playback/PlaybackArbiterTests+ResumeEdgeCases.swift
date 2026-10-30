import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Resume edge cases

    /// The music is paused for Viewer, and the user stops or quits the player
    /// (`found`) with no report saying so: Viewer's stop finds it so.
    private func skipResume(_ arbiter: PlaybackArbiter, player: MockMusicPlayer, found: PlayerState) async {
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.overrideState(found) // the user, and no report says so
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
    }

    @Test("a resume that finds the player stopped or quit, with no report saying so, is skipped, and the music shows idle",
          arguments: [PlayerState.stopped, .notRunning])
    func resumeSkippedWhenFoundStopped(_ found: PlayerState) async {
        let player = MockMusicPlayer(state: .playing)
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { states.append($0) }))

        await skipResume(arbiter, player: player, found: found)
        #expect(await player.playCallCount == 0)
        #expect(states.value.last == .musicIdle)
    }

    @Test("a resume skipped for a player found stopped or quit ends our pause: opened paused, another app's start and stop doesn't play it",
          arguments: [PlayerState.stopped, .notRunning])
    func skippedResumeEndsPause(_ found: PlayerState) async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)
        await skipResume(arbiter, player: player, found: found)

        await player.overrideState(.paused)
        await arbiter.handlePlayerStateChange(.paused) // the user opens it paused: a report that keeps a pause of ours
        await arbiter.sourceChanged("com.apple.Safari", playing: true)
        await arbiter.sourceChanged("com.apple.Safari", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("with several apps playing, the music resumes once, when the last one stops")
    func resumesOnceAfterLastStops() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("com.example.videoplayer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0) // the other video player still plays

        await arbiter.sourceChanged("com.example.videoplayer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 1)
    }

    @Test("with Stay paused after calls, a call playing as the fade-out begins counts, though it ends before the music is paused")
    func callEndingDuringFadeOutCounts() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() })
        await arbiter.refreshPlaybackState() // as monitoring starts
        let call = "us.zoom.xos"
        await arbiter.handleCallChange(sourceID: call, inCall: true)
        await arbiter.handleSourceChange(sourceID: call, isPlaying: true)
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
        await arbiter.handleCallChange(sourceID: call, inCall: false) // the call ends; its app plays on
        await steps.letGo(2)
        await arbiter.waitForPause()
        #expect(await player.state == .paused)

        await arbiter.sourceChanged(call, playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("with Stay paused after calls, an app's call that ended before its sound came on doesn't count: the music comes back")
    func endedCallForgotten() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: configuration)
        let call = "us.zoom.xos"
        await arbiter.handleCallChange(sourceID: call, inCall: true)
        await arbiter.handleCallChange(sourceID: call, inCall: false) // over before it plays
        await arbiter.sourceChanged(call, playing: true) // its sound, with no call
        await arbiter.sourceChanged(call, playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("with Auto-Pause off, a resume that fails while an app plays is tried again: the music comes back regardless")
    func failedResumeRetriedWithAutoPauseOff() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.setAutoPauseEnabled(false) // resumes at once, while Viewer plays
        await TestWait.until { scheduler.scheduledDelays == [PlaybackArbiter.resumeRetryDelay] } // the retry
        #expect(await player.playCallCount == 1)

        await player.setFailPlay(nil)
        await scheduler.completeNext()
        await TestWait.until { await player.playCallCount == 2 }
        #expect(await player.state == .playing)
    }

    @Test("with Level the volume on, a resume tried again that finds an app playing, Auto-Pause on again, puts the volume back")
    func retryFindingAppPutsLevelBack() async {
        let player = MockMusicPlayer()
        let leveler = RecordingVolumeLeveler()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeLevelingArbiter(player, leveler: leveler, scheduler: scheduler)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.setAutoPauseEnabled(false) // the resume lowers the volume, fails, and waits to try again
        await TestWait.until { scheduler.scheduledDelays == [PlaybackArbiter.resumeRetryDelay] }
        #expect(leveler.log == ["lower -6.0"])

        await arbiter.setAutoPauseEnabled(true) // Viewer still plays: a pause waits for it to be measured again
        await scheduler.completeNext() // the retry, which finds Viewer playing
        await TestWait.until { leveler.log.count == 2 }
        #expect(leveler.log == ["lower -6.0", "restore now"])
    }
}
