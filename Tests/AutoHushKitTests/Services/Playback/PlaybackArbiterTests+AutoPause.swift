import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Auto-pause on/off

    @Test("with auto-pause off, a foreign source does not pause the player")
    func autoPauseOffDoesNotPause() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(), autoPauseEnabled: false)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    @Test("turning auto-pause off resumes the player if we paused it")
    func turningOffResumes() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(false)
        await TestWait.until { await player.playCallCount == 1 } // the resume runs on its own

        #expect(await player.playCallCount == 1)
        #expect(await player.state == .playing)
    }

    @Test("turning auto-pause off leaves the player alone when the user paused it")
    func turningOffRespectsUserPause() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty)
    }

    @Test("turning auto-pause off just as the last app stops resumes the music once")
    func turningOffCancelsPendingResume() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.setAutoPauseEnabled(false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 1) // not a second time
    }

    @Test("with auto-pause off, an app that starts doesn't call off resuming the music we paused")
    func startDoesNotCancelResumeWhileOff() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setUnansweredStateQueries(1) // the resume will have to be retried
        await arbiter.setAutoPauseEnabled(false)
        await TestWait.until { scheduler.scheduledDelays.count == 1 } // the retry is scheduled
        await arbiter.sourceChanged("com.google.Chrome", playing: true)
        await scheduler.completeNext()

        await TestWait.until { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
    }

    @Test("turning auto-pause back on pauses the player for an app still playing once it is measured again")
    func turningOnPausesForActiveSource() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(
            player: player, configuration: .testing, debounceScheduler: scheduler, autoPauseEnabled: false
        )

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(true)
        #expect(await player.pauseCallCount == 0) // not until VLC has been measured again
        #expect(scheduler.scheduledDelays == [AppConfiguration.testing.sourceStopGrace + PlaybackArbiter.remeasureMargin])

        await scheduler.completeNext()
        await TestWait.until { await player.pauseCallCount == 1 }
        #expect(await player.pauseCallCount == 1)
    }

    @Test("turning auto-pause back on doesn't pause the player for an app found silent meanwhile")
    func turningOnIgnoresAppFoundSilent() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(
            player: player, configuration: .testing, debounceScheduler: scheduler, autoPauseEnabled: false
        )

        // While auto-pause is off nothing is measured: a muted call with its
        // output open counts as playing until the monitor measures it again.
        await arbiter.sourceChanged("us.zoom.xos", playing: true)
        await arbiter.setAutoPauseEnabled(true) // e.g. a snooze ends
        await arbiter.sourceChanged("us.zoom.xos", playing: false)
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.playCallCount == 0)
    }

    @Test("turning auto-pause off again calls off the pause it was waiting to make")
    func turningOffCancelsPendingPause() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(
            player: player, configuration: .testing, debounceScheduler: scheduler, autoPauseEnabled: false
        )

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(true)
        await arbiter.setAutoPauseEnabled(false)
        await scheduler.completeNext()
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 0)
    }

    @Test("an app that starts while auto-pause waits to re-measure pauses the player at once")
    func newSourceDuringRemeasurePausesAtOnce() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(
            player: player, configuration: .testing, debounceScheduler: scheduler, autoPauseEnabled: false
        )

        await arbiter.sourceChanged("us.zoom.xos", playing: true)
        await arbiter.setAutoPauseEnabled(true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 1)

        await scheduler.completeNext() // the wait it called off
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("turning auto-pause back on with nothing playing does nothing")
    func turningOnIdleDoesNothing() async {
        let player = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(), debounceScheduler: scheduler,
                                      autoPauseEnabled: false)

        await arbiter.setAutoPauseEnabled(true)
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty) // no pause waits to be made either
    }

    @Test("a new configuration's stop grace applies to the next wait to re-measure")
    func configurationUpdate() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(
            player: player, configuration: .testing, debounceScheduler: scheduler, autoPauseEnabled: false
        )

        await arbiter.setConfiguration(AppConfiguration(timings: TimingSettings(stopGrace: 4)))
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(true)

        #expect(scheduler.scheduledDelays == [4 + PlaybackArbiter.remeasureMargin])
    }

    @Test("a new configuration's fade-out length applies to the next pause")
    func newFadeOutLength() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let sleeps = Locked<[TimeInterval]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(), fadeSleep: { sleeps.append($0) })

        await arbiter.setConfiguration(AppConfiguration(timings: TimingSettings(fadeOutDuration: 0.5)))
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
        #expect(sleeps.value.filter { $0 == VolumeFader.stepInterval }.count == 5) // not the first second's 10
    }

    // MARK: - When audio levels are needed (recording indicator)

    @Test("levels are needed only while the player plays here or is paused by us, with auto-pause on")
    func audioLevelsNeeded() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let log = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(), debounceScheduler: scheduler,
            onAudioLevelsNeededChange: { log.append($0) }
        )

        await arbiter.refreshPlaybackState()                       // The player paused by the user
        await arbiter.handlePlayerStateChange(.playing)           // plays here
        await player.overrideState(.playing)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true) // we pause it: still needed
        await arbiter.setAutoPauseEnabled(false)                   // resumed and off: not needed
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.setAutoPauseEnabled(true)                    // on again; VLC is still active, so the player is paused again
        await arbiter.waitForPause()
        await arbiter.handlePlayerStateChange(.stopped)           // the user takes over

        #expect(log.value == [false, true, false, true, false])
    }

    @Test("levels are not needed while the player plays on another device")
    func audioLevelsNotNeededElsewhere() async {
        let log = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .playing), configuration: AppConfiguration(),
            onAudioLevelsNeededChange: { log.append($0) }
        )
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.handleLocalPlaybackChange(false)
        #expect(log.value == [true, false])
    }
}
