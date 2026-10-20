import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Taking over a pause after an update

    @Test("a pause taken over after a restart ends when no app is found playing, after the monitor's longest start (AntiDot mode's) and a margin",
          arguments: [nil, 3, 2] as [TimeInterval?])
    func takenOverPauseResumes(longestStart: TimeInterval?) async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let clock = ManualClock()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler, clock: { clock.now })

        #expect(await arbiter.takeOverPause()) // it was paused: taken over
        let usual = AppConfiguration.testing.sourceStartConfirmation + PlaybackArbiter.takeOverMargin
        #expect(scheduler.scheduledDelays == [usual])
        // The monitor, started after the takeover, says how long apps take to count.
        clock.advance(by: 1)
        if let longestStart { await arbiter.handleStartConfirmationChange(longestStart) }
        let waits = longestStart.map { [usual, $0 + PlaybackArbiter.takeOverMargin - 1] } ?? [usual] // from the takeover
        #expect(scheduler.scheduledDelays == waits)
        #expect(await player.playCallCount == 0)

        for _ in waits { await scheduler.completeNext() } // no app turned up
        await TestWait.until { await player.playCallCount == 1 }
        #expect(await player.state == .playing)
    }

    @Test("a taken-over pause holds while an app is still playing, and ends when it stops")
    func takenOverPauseHoldsForPlayingApp() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onPlaybackStateChange: { stateStream.yield($0) })

        await arbiter.takeOverPause()
        _ = await nextState(from: stateStream.stream) // drain the take-over's state
        await arbiter.sourceChanged("org.videolan.vlc", playing: true) // found again: the resume is called off
        #expect(await nextState(from: stateStream.stream) == .pausedByMonitor)
        await scheduler.completeNext() // the wait it called off
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.pauseCallCount == 0) // already paused

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("music playing again by the time AutoHush restarts is not taken over")
    func nothingToTakeOver() async {
        let player = MockMusicPlayer(state: .playing) // the user pressed play meanwhile
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        #expect(await !arbiter.takeOverPause()) // no pause to take over
        await arbiter.waitUntilIdle()
        #expect(scheduler.scheduledDelays.isEmpty)
        #expect(await player.playCallCount == 0)
    }

    @Test("with auto-pause off, a taken-over pause ends at once")
    func takenOverPauseWithAutoPauseOff() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      autoPauseEnabled: false)

        await arbiter.takeOverPause()
        await TestWait.until { await player.playCallCount == 1 }
        #expect(scheduler.scheduledDelays.isEmpty)
    }

    // MARK: - A pause made by an app as it starts (VLC pauses Spotify and Music)

    @Test("music another app pauses as it starts comes back when that app stops, with no pause of ours")
    func takesOverPauseOfStartingApp() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let states = Locked<[PlaybackState]>([])
        let needs = Locked<[Bool]>([])
        let arbiter = await makeClockedArbiter(player: player, clock: clock,
                                               onPlaybackStateChange: { states.append($0) },
                                               onAudioLevelsNeededChange: { needs.append($0) })
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter) // VLC pauses it
        clock.advance(by: 0.2)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)

        #expect(await player.pauseCallCount == 0)
        #expect(states.value.last == .pausedByMonitor)
        #expect(needs.value == [true, false, true]) // levels kept to hear VLC stop

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["play"])
        #expect(await player.state == .playing)
    }

    @Test("a pause seen just before the app was first heard counts too: the monitor hears an app a tick late")
    func takesOverPauseJustBeforeHeard() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        await pausedElsewhere(player, arbiter)
        clock.advance(by: PlaybackArbiter.hearingDelay)
        let heard = clock.now
        clock.advance(by: 0.5)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("music the user paused before the app was heard stays paused afterwards", arguments: [0.6, 2.0, 60.0])
    func leavesUsersEarlierPause(secondsBefore: TimeInterval) async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        await pausedElsewhere(player, arbiter) // the user
        clock.advance(by: secondsBefore)
        let heard = clock.now
        clock.advance(by: 0.5)
        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: true, heardSince: heard)
        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("a pause well after the app was first heard, while it isn't counted yet, is the user's (AntiDot's 3 s)",
          arguments: [1.5, 2.5])
    func leavesUsersPauseWhileAppIsConfirmed(secondsAfterHeard: TimeInterval) async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: secondsAfterHeard)
        await pausedElsewhere(player, arbiter) // the user, as the other app waits to count
        clock.advance(by: 3 - secondsAfterHeard)
        await arbiter.sourceChanged("com.apple.podcasts", playing: true, heardSince: heard)
        await arbiter.sourceChanged("com.apple.podcasts", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("a pause the check finds before the player has reported it is taken over too")
    func takesOverPauseFoundByCheck() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: 0.3)
        await player.overrideState(.paused) // no report yet
        clock.advance(by: 0.2)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await arbiter.handlePlayerStateChange(.paused) // the report, late

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a player whose reports come late: only a pause surely after the app was heard is taken over",
          arguments: [(0.3, false), (0.7, true)])
    func allowsForLateReports(reportedAfterHeard: TimeInterval, isTakenOver: Bool) async {
        let player = MockMusicPlayer(stateReportDelay: 1) // read once a second
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: reportedAfterHeard) // it may have paused up to a second before
        await pausedElsewhere(player, arbiter)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        if isTakenOver { await TestWait.until { await player.playCallCount == 1 } } else { await arbiter.waitUntilIdle() }

        #expect(await player.playCallCount == (isTakenOver ? 1 : 0))
    }

    @Test("an app that starts without a known first sound (no longer ignored) takes over no pause")
    func noTakeOverWithoutFirstHeard() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        await pausedElsewhere(player, arbiter)
        clock.advance(by: 0.1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("a player stopped, rather than paused, as an app starts isn't taken over")
    func noTakeOverOfStoppedPlayer() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: 0.3)
        await player.overrideState(.stopped)
        await arbiter.handlePlayerStateChange(.stopped)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("the user playing the music again while the app plays ends the taken-over pause")
    func userEndsTakenOverPause() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await player.overrideState(.playing)
        await arbiter.handlePlayerStateChange(.playing) // the user
        await player.overrideState(.paused)
        await arbiter.handlePlayerStateChange(.paused) // and the user again, long after VLC started
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("a check long after the app started (auto-pause turned back on) takes over nothing")
    func noTakeOverInLateCheck() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let scheduler = ManualDebounceScheduler()
        let arbiter = await makeClockedArbiter(player: player, clock: clock, scheduler: scheduler,
                                               autoPauseEnabled: false)
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        clock.advance(by: 10)
        await arbiter.setAutoPauseEnabled(true)
        clock.advance(by: AppConfiguration.testing.sourceStopGrace + PlaybackArbiter.remeasureMargin)
        await scheduler.completeNext() // the pause check, once VLC is measured again
        await TestWait.until { await player.stateQueryCount == 2 } // after the one at start-up
        await arbiter.waitForPause()
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("music the user pauses during the fade-out stays theirs, even right after the app was heard")
    func userPauseDuringFadeOutIsNotTakenOver() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let clock = ManualClock()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await makeClockedArbiter(player: player, clock: clock, configuration: AppConfiguration(),
                                               fadeSleep: { _ in await steps.step() })
        let heard = clock.now
        clock.advance(by: 0.5)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true, heardSince: heard)
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
        clock.advance(by: 0.2)
        await pausedElsewhere(player, arbiter) // the user
        await steps.letGo(2)
        await arbiter.waitForPause()
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.playCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("an app that stops while the player is checked: the pause taken over ends at once")
    func takenOverPauseEndsWhenAppStoppedDuringCheck() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        await player.setBeforeStateAnswer { [arbiter, player] in // once
            await player.setBeforeStateAnswer(nil)
            await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        }
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)

        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a player paused here is taken over even once its output has closed (an app counted after 3 s)")
    func takesOverPauseAfterOutputClosed() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        clock.advance(by: 2.5)
        await arbiter.handleLocalPlaybackChange(false) // its output closes
        clock.advance(by: 0.2)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("a pause on another device (Spotify Connect) is never taken over")
    func noTakeOverOfRemotePause() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock)
        await arbiter.handleLocalPlaybackChange(false) // it plays on another device
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("with auto-pause off, an app's pause is never taken over")
    func noTakeOverWithAutoPauseOff() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let arbiter = await makeClockedArbiter(player: player, clock: clock, autoPauseEnabled: false)
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.commandLog.isEmpty)
    }

    @Test("with Level the volume on, a resume that never takes puts the Mac's volume back as it gives up, not while it retries")
    func levelingGivesUpWithResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let leveler = RecordingVolumeLeveler()
        let arbiter = makeLevelingArbiter(player, leveler: leveler, scheduler: scheduler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            #expect(!leveler.log.contains("restore now")) // tried again: still lowered
            await scheduler.completeNext()
        }
        await TestWait.until { leveler.log.last == "restore now" }
        await arbiter.waitUntilIdle()
        #expect(leveler.log == Array(repeating: "lower -6.0", count: PlaybackArbiter.resumeRetries + 1) + ["restore now"])
        #expect(await player.playCallCount == PlaybackArbiter.resumeRetries + 1)
    }

    /// What happens to a resume that lowered the Mac's volume and failed,
    /// before it's tried again.
    enum BeforeRetry: String, CaseIterable, Sendable {
        case playerStopped, playerPlays, noAnswer, appStarts, userTookOver, staysPausedAfterCall, resumesHeld, macSleeps
    }

    /// With Level the volume on, a resume lowers the Mac's volume and fails,
    /// then `before` happens before it's tried again: what the volume leveler
    /// was asked by then, and how many times the music was played.
    private func levelingAfterFailedResume(_ before: BeforeRetry) async -> (log: [String], plays: Int) {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let leveler = RecordingVolumeLeveler()
        let arbiter = makeLevelingArbiter(player, leveler: leveler, scheduler: scheduler)
        let call = "us.zoom.xos"
        if before == .staysPausedAfterCall { await arbiter.handleCallChange(sourceID: call, inCall: true) }
        let app = before == .staysPausedAfterCall ? call : "org.videolan.vlc"
        await arbiter.sourceChanged(app, playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged(app, playing: false)
        await TestWait.until { scheduler.scheduledDelays.count == 1 } // failed: tried again in a second
        #expect(leveler.log == ["lower -6.0"])
        await player.setFailPlay(nil)

        switch before {
        case .playerStopped:
            await player.overrideState(.stopped) // it quit meanwhile
            await scheduler.completeNext()
        case .playerPlays:
            await player.overrideState(.playing) // the play went through after all
            await scheduler.completeNext()
        case .noAnswer:
            await player.setUnansweredStateQueries(.max)
            await scheduler.completeNext()
            await TestWait.until { scheduler.scheduledDelays.count == 2 } // no answer: once more
            await scheduler.completeNext()
        case .appStarts:
            await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        case .userTookOver:
            await player.overrideState(.stopped)
            await arbiter.handlePlayerStateChange(.stopped)
            await scheduler.completeNext()
        case .staysPausedAfterCall:
            var staysPaused = AppConfiguration.testing
            staysPaused.levelsMusic = true
            staysPaused.staysPausedAfterCalls = true // turned on meanwhile
            await arbiter.setConfiguration(staysPaused)
            await scheduler.completeNext()
        case .resumesHeld:
            await arbiter.holdResumes(true)
        case .macSleeps:
            await arbiter.setAsleep(true)
        }
        await arbiter.waitUntilIdle()
        let result = (leveler.log, await player.playCallCount)
        await arbiter.shutdown()
        return result
    }

    @Test("with Level the volume on, a failed resume that doesn't bring the music back at its retry puts the lowered volume back at once",
          arguments: BeforeRetry.allCases.filter { $0 != .playerPlays })
    func levelingPutBackWithoutMusic(_ before: BeforeRetry) async {
        let run = await levelingAfterFailedResume(before)
        #expect(run.log == ["lower -6.0", "restore now"])
        #expect(run.plays == 1)
    }

    @Test("with Level the volume on, a failed resume whose music plays after all at its retry keeps the volume lowered for it")
    func levelingKeptForMusicPlaying() async {
        let run = await levelingAfterFailedResume(.playerPlays)
        #expect(run.log == ["lower -6.0"])
        #expect(run.plays == 1)
    }
}
