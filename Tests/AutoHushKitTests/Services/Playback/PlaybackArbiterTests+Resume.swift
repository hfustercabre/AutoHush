import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Resume behaviour

    @Test("resumes the player as soon as the other app stops", arguments: [
        "org.videolan.vlc",
        "com.google.Chrome.helper", // a browser's helper process
    ])
    func resumesAfterSourceStops(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)
        await arbiter.sourceChanged(sourceID, playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.state == .playing)
        #expect(await player.playCallCount == 1)
    }

    @Test("with Stay paused after calls, a call during the pause (or the one it began for) keeps the music paused once the apps stop; with no call, or the setting off, it resumes")
    func staysPausedAfterCalls() async {
        func run(staysPaused: Bool, call: String?, callFirst: Bool = false) async -> Int {
            var configuration = AppConfiguration.testing
            configuration.staysPausedAfterCalls = staysPaused
            let player = MockMusicPlayer()
            let arbiter = makeArbiter(player: player, configuration: configuration)
            if callFirst, let call {
                await arbiter.handleCallChange(sourceID: call, inCall: true) // the pause begins for it
                await arbiter.sourceChanged(call, playing: true)
            } else {
                await arbiter.sourceChanged("org.videolan.vlc", playing: true)
                if let call {
                    await arbiter.handleCallChange(sourceID: call, inCall: true)
                    await arbiter.sourceChanged(call, playing: true)
                }
            }
            if let call {
                await arbiter.handleCallChange(sourceID: call, inCall: false) // ended before the apps stop
                await arbiter.sourceChanged(call, playing: false)
            }
            if !callFirst { await arbiter.sourceChanged("org.videolan.vlc", playing: false) }
            if !(staysPaused && call != nil) { await TestWait.until { await player.playCallCount == 1 } }
            await arbiter.waitUntilIdle()
            return await player.playCallCount
        }
        #expect(await run(staysPaused: true, call: "us.zoom.xos") == 0)
        #expect(await run(staysPaused: true, call: "us.zoom.xos", callFirst: true) == 0)
        #expect(await run(staysPaused: true, call: nil) == 1)
        #expect(await run(staysPaused: false, call: "us.zoom.xos") == 1)
    }

    /// How a pause attempt ends with nothing paused, for `callForgottenWithoutPause`.
    enum NoPause: CaseIterable, Sendable {
        case fadeCalledOff, pauseFailed, stillLearning
    }

    @Test("with Stay paused after calls, a call during a pause attempt that paused nothing (its fade-out called off, the pause failed, the player's controls still learned) is forgotten: a later pause with no call resumes",
          arguments: NoPause.allCases)
    func callForgottenWithoutPause(_ noPause: NoPause) async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() })
        await arbiter.refreshPlaybackState() // as monitoring starts
        let call = "us.zoom.xos"
        await arbiter.handleCallChange(sourceID: call, inCall: true)
        switch noPause {
        case .fadeCalledOff:
            await player.setVolumeLevel(60)
            await arbiter.handleSourceChange(sourceID: call, isPlaying: true)
            await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
            await arbiter.handleSourceChange(sourceID: call, isPlaying: false) // the call's sound stops
            await steps.letGo(2)
        case .pauseFailed, .stillLearning:
            await player.setFailPause(noPause == .pauseFailed ? StubError.failed : MusicPlayerError.stillLearning)
            await arbiter.sourceChanged(call, playing: true)
            await player.setFailPause(nil)
            await arbiter.sourceChanged(call, playing: false)
        }
        await arbiter.handleCallChange(sourceID: call, inCall: false)
        await arbiter.waitUntilIdle()
        #expect(await player.state == .playing) // never paused

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.state == .paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    /// A pause with no fade-out of ours, for `callNotedWithoutFadeOut`.
    enum PauseWithoutFade: CaseIterable, Sendable {
        case takenOver, muted
    }

    @Test("with Stay paused after calls, a call already playing when the pause is a starting app's taken over, or a mute, keeps the music paused once it stops",
          arguments: PauseWithoutFade.allCases)
    func callNotedWithoutFadeOut(_ pause: PauseWithoutFade) async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let call = "us.zoom.xos"
        let player = MockMusicPlayer()
        let states = Locked<[PlaybackState]>([])
        let clock = ManualClock()
        let arbiter: PlaybackArbiter
        switch pause {
        case .takenOver:
            arbiter = await makeClockedArbiter(player: player, clock: clock, configuration: configuration,
                                               onPlaybackStateChange: { states.append($0) })
        case .muted:
            await player.overrideState(.paused)
            await player.setPlaysAnyway(true) // a web app's ad
            arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: configuration,
                                      debounceScheduler: ManualDebounceScheduler(), onPlaybackStateChange: { states.append($0) })
        }
        await arbiter.handleCallChange(sourceID: call, inCall: true)
        let heard = clock.now
        if pause == .takenOver {
            clock.advance(by: 0.3)
            await pausedElsewhere(player, arbiter) // the call app pauses the music as it starts
        }
        await arbiter.sourceChanged(call, playing: true, heardSince: pause == .takenOver ? heard : nil)
        #expect(states.value.last == .pausedByMonitor) // the pause is ours
        await arbiter.handleCallChange(sourceID: call, inCall: false)
        await arbiter.sourceChanged(call, playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
        // A mute standing in for the pause isn't left on: the player is paused for real.
        #expect(await player.commandLog.contains("forgetPause") == (pause == .muted))
    }

    @Test("with Stay paused after calls, an app already playing that starts a call during the pause (a browser tab joining one) keeps the music paused once it stops")
    func callFromAppAlreadyPlaying() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: configuration)

        await arbiter.sourceChanged("com.google.Chrome", playing: true)
        await arbiter.handleCallChange(sourceID: "com.google.Chrome", inCall: true) // only the call says so: no new start
        await arbiter.handleCallChange(sourceID: "com.google.Chrome", inCall: false)
        await arbiter.sourceChanged("com.google.Chrome", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 1)
        #expect(await player.playCallCount == 0)
    }

    @Test("with Stay paused after calls, the call keeps only its own pause: once the user plays the music, the next pause, with no call, resumes")
    func callKeepsOnlyItsPause() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: configuration)
        let call = "us.zoom.xos"

        await arbiter.handleCallChange(sourceID: call, inCall: true)
        await arbiter.sourceChanged(call, playing: true)
        await arbiter.handleCallChange(sourceID: call, inCall: false)
        await arbiter.sourceChanged(call, playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0) // kept paused after the call

        await player.overrideState(.playing)
        await arbiter.handlePlayerStateChange(.playing) // the user plays it again
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("with Stay paused after calls, the music kept paused is no longer ours: levels aren't needed, it shows idle, and once the setting is off another app's start and stop doesn't play it")
    func keptPausedIsNoLongerOurs() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let states = Locked<[PlaybackState]>([])
        let needs = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) },
                                      onAudioLevelsNeededChange: { needs.append($0) })
        let call = "us.zoom.xos"

        await arbiter.handleCallChange(sourceID: call, inCall: true)
        await arbiter.sourceChanged(call, playing: true)
        await arbiter.handleCallChange(sourceID: call, inCall: false)
        await arbiter.sourceChanged(call, playing: false)
        await arbiter.waitUntilIdle()
        #expect(needs.value == [true, false])
        #expect(states.value.last == .musicIdle)

        configuration.staysPausedAfterCalls = false
        await arbiter.setConfiguration(configuration)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the monitor is told the music is paused by us once as it pauses, and once more as it resumes")
    func tellsPausedByUs() async {
        let player = MockMusicPlayer()
        let told = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPausedByUsChange: { told.append($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("com.apple.Safari", playing: true) // still paused
        await arbiter.sourceChanged("com.apple.Safari", playing: false)
        #expect(told.value == [true])

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(told.value == [true, false])
    }

    @Test("with Level the volume on, the Mac's volume is lowered by the monitor's offset before the music resumes, and put back as it fades out for an app; off, never lowered; turning it off puts back whatever is lowered, stopping only what it lowered")
    func levelsMusic() async {
        func run(levels: Bool, offset: Float?, turnsOff: Bool = false) async -> (log: [String], plays: Int) {
            var configuration = AppConfiguration.testing
            configuration.levelsMusic = levels
            let player = MockMusicPlayer()
            let leveler = RecordingVolumeLeveler()
            let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                          fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { offset })
            for plays in 1...2 {
                await arbiter.sourceChanged("org.videolan.vlc", playing: true)
                await arbiter.sourceChanged("org.videolan.vlc", playing: false)
                await TestWait.until { await player.playCallCount == plays }
                await arbiter.waitUntilIdle()
            }
            if turnsOff {
                var off = configuration
                off.levelsMusic = false
                await arbiter.setConfiguration(off)
            }
            await arbiter.shutdown()
            return (leveler.log, await player.playCallCount)
        }
        let fadeOut = AppConfiguration.testing.fadeOutDuration
        let cycle = ["lower -6.0", "restore over \(fadeOut)", "lower -6.0"]
        let stops = await run(levels: true, offset: -6)
        #expect(stops.log == cycle + ["restore now"] && stops.plays == 2)
        let turnedOff = await run(levels: true, offset: -6, turnsOff: true)
        #expect(turnedOff.log == cycle + ["restore now (any)"] && turnedOff.plays == 2) // nothing left for the stop
        let quieter = await run(levels: true, offset: nil) // the apps weren't quieter
        #expect(quieter.log.isEmpty && quieter.plays == 2)
        let off = await run(levels: false, offset: -6)
        #expect(off.log.isEmpty && off.plays == 2)
    }

    @Test("the volume lowered by another monitoring (the app's one leveler) is never put back by this one's pause or stop")
    func levelingOnlyItsOwn() async {
        let leveler = RecordingVolumeLeveler()
        let other = leveler.lower(by: -4) // the player chosen now, as it resumed
        let player = MockMusicPlayer()
        let arbiter = makeLevelingArbiter(player, leveler: leveler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.shutdown()
        #expect(other != nil)
        #expect(leveler.log == ["lower -4.0", "lower -6.0"]) // lowered already: nothing of its own to put back
        #expect(await player.playCallCount == 1)
    }

    @Test("retries the resume when the player does not answer, instead of giving up")
    func retriesUnansweredResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setUnansweredStateQueries(1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { scheduler.scheduledDelays.count == 1 } // the retry, a second later
        #expect(await player.playCallCount == 0)

        await scheduler.completeNext()
        await TestWait.until { await player.playCallCount == 1 }
        #expect(scheduler.scheduledDelays == [PlaybackArbiter.resumeRetryDelay])
    }

    @Test("stops retrying once the player has not answered every retry")
    func givesUpAfterRetries() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        let queries = pauseQueries + PlaybackArbiter.resumeRetries + 1 // then the resume's, and the retries'
        await TestWait.until { await player.stateQueryCount >= queries }
        await arbiter.waitUntilIdle()
        #expect(await player.stateQueryCount == queries)
        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries)
    }

    @Test("a resume whose command doesn't take is tried again")
    func retriesFailedResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { scheduler.scheduledDelays.count == 1 } // the retry, a second later
        #expect(await player.playCallCount == 1)

        await player.setFailPlay(nil)
        await scheduler.completeNext()
        await TestWait.until { await player.playCallCount == 2 }
        #expect(await player.state == .playing)
        #expect(scheduler.scheduledDelays == [PlaybackArbiter.resumeRetryDelay])
    }

    @Test("a resume that never takes is given up after its retries")
    func givesUpFailedResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { await player.playCallCount == PlaybackArbiter.resumeRetries + 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == PlaybackArbiter.resumeRetries + 1)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries)
    }

    // MARK: - Resume edge cases

    @Test("a resume that finds the player stopped or quit (no report said so) is skipped, and the pause is no longer ours: once the user opens it paused, another app's start and stop doesn't play it",
          arguments: [PlayerState.stopped, .notRunning])
    func resumeSkippedWhenFoundStopped(_ found: PlayerState) async {
        let player = MockMusicPlayer(state: .playing)
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.overrideState(found) // the user, and no report says so
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(states.value.last == .musicIdle)

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

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("com.colliderli.iina", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0) // IINA still plays

        await arbiter.sourceChanged("com.colliderli.iina", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 1)
    }
}
