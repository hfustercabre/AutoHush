import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Resume behaviour

    @Test("resumes the player as soon as the other app stops", arguments: [
        "org.example.viewer",
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

    @Test("a polled player is asked again a moment after a resume: one that stopped meanwhile shows as not playing, not as playing elsewhere",
          arguments: [true, false])
    func resumeConfirmedLater(keepsPlaying: Bool) async {
        let player = MockMusicPlayer(stateReportDelay: 1) // read once a second
        let scheduler = ManualDebounceScheduler()
        let published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: statuses(playback: { published.set($0) }))
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(scheduler.scheduledDelays.last == PlaybackArbiter.resumeConfirmDelay)
        // Stopped right after, unannounced: its last read was the pause's, so its
        // observer has no change to report (a TV app, its window closed during
        // the fade-in), and its output closes.
        if !keepsPlaying {
            await player.setState(.paused)
            await arbiter.handleLocalPlaybackChange(false)
            #expect(published.state == .playingElsewhere) // as it was shown
        }
        await scheduler.completeNext()
        let expected: PlaybackState = keepsPlaying ? .musicPlaying : .musicIdle
        await TestWait.until { published.state == expected }
        #expect(published.state == expected)
    }

    @Test("a polled player is asked again after a resume though an app played and stopped meanwhile: the resume that came of it, with no pause to end, is over")
    func resumeConfirmedAfterAppCameAndWent() async {
        let player = MockMusicPlayer(stateReportDelay: 1) // read once a second
        let scheduler = ManualDebounceScheduler()
        let published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: statuses(playback: { published.set($0) }))
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        // Stopped right after, unannounced, its output closed; then an app
        // plays and stops before it's asked again: nothing to pause or resume.
        await player.setState(.paused)
        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("com.example.movies", playing: true)
        await arbiter.sourceChanged("com.example.movies", playing: false)
        await arbiter.waitUntilIdle()
        #expect(published.state == .playingElsewhere) // as it was shown
        await scheduler.completeNext()
        await TestWait.until { published.state == .musicIdle }
        #expect(published.state == .musicIdle)
    }

    /// The playback state last published.
    final class LastPublished: Sendable {
        private let last = Locked<PlaybackState?>(nil)
        var state: PlaybackState? { last.value }
        func set(_ state: PlaybackState) { last.value = state }
    }

    @Test("a player that announces its state isn't asked again after a resume")
    func announcingPlayerNotAskedAgain() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(!scheduler.scheduledDelays.contains(PlaybackArbiter.resumeConfirmDelay))
    }

    /// How many times the music is played once the apps stop, with Stay
    /// paused after calls `staysPaused`: after a pause for Viewer that `call`
    /// joins, or one that began for the call (`callFirst`).
    private func playsAfterPause(staysPaused: Bool, call: String?, callFirst: Bool = false) async -> Int {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = staysPaused
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: configuration)
        if callFirst, let call {
            await arbiter.handleCallChange(sourceID: call, inCall: true) // the pause begins for it
            await arbiter.sourceChanged(call, playing: true)
        } else {
            await arbiter.sourceChanged("org.example.viewer", playing: true)
            if let call {
                await arbiter.handleCallChange(sourceID: call, inCall: true)
                await arbiter.sourceChanged(call, playing: true)
            }
        }
        if let call {
            await arbiter.handleCallChange(sourceID: call, inCall: false) // ended before the apps stop
            await arbiter.sourceChanged(call, playing: false)
        }
        if !callFirst { await arbiter.sourceChanged("org.example.viewer", playing: false) }
        if !(staysPaused && call != nil) { await TestWait.until { await player.playCallCount == 1 } }
        await arbiter.waitUntilIdle()
        return await player.playCallCount
    }

    @Test("with Stay paused after calls, a call during the pause, or the one it began for, keeps the music paused once the apps stop",
          arguments: [false, true])
    func staysPausedAfterCalls(callFirst: Bool) async {
        #expect(await playsAfterPause(staysPaused: true, call: "us.zoom.xos", callFirst: callFirst) == 0)
    }

    @Test("with Stay paused after calls, a pause with no call resumes once the apps stop")
    func resumesAfterPauseWithoutCall() async {
        #expect(await playsAfterPause(staysPaused: true, call: nil) == 1)
    }

    @Test("with Stay paused after calls off, a call during the pause doesn't keep the music paused")
    func resumesAfterCallWithSettingOff() async {
        #expect(await playsAfterPause(staysPaused: false, call: "us.zoom.xos") == 1)
    }

    /// How a pause attempt ends with nothing paused, for `callForgottenWithoutPause`:
    /// its fade-out called off, the pause failed, or the player's controls still learned.
    enum NoPause: CaseIterable, Sendable {
        case fadeCalledOff, pauseFailed, stillLearning
    }

    @Test("with Stay paused after calls, a call during a pause attempt that paused nothing is forgotten: a later pause with no call resumes",
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

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        #expect(await player.state == .paused)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
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
                                      debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { states.append($0) }))
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

    @Test("with Stay paused after calls, a call started during the pause by an app already playing (a browser tab joining one) keeps the music paused")
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
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    /// A call's app pauses the music, and stops once its call is over: with
    /// Stay paused after calls, the music is kept paused.
    private func keepPausedAfterCall(_ arbiter: PlaybackArbiter) async {
        let call = "us.zoom.xos"
        await arbiter.handleCallChange(sourceID: call, inCall: true)
        await arbiter.sourceChanged(call, playing: true)
        await arbiter.handleCallChange(sourceID: call, inCall: false)
        await arbiter.sourceChanged(call, playing: false)
        await arbiter.waitUntilIdle()
    }

    @Test("with Stay paused after calls, the music kept paused is no longer ours: levels aren't needed, and it shows idle")
    func keptPausedIsNoLongerOurs() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let states = Locked<[PlaybackState]>([])
        let needs = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(), configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { states.append($0) }),
                                      onAudioLevelsNeededChange: { needs.append($0) })

        await keepPausedAfterCall(arbiter)
        #expect(needs.value == [true, false])
        #expect(states.value.last == .musicIdle)
    }

    @Test("with Stay paused after calls, the music kept paused isn't played by another app's start and stop once the setting is off")
    func keptPausedStaysPausedWithSettingOff() async {
        var configuration = AppConfiguration.testing
        configuration.staysPausedAfterCalls = true
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: configuration)
        await keepPausedAfterCall(arbiter)

        configuration.staysPausedAfterCalls = false
        await arbiter.setConfiguration(configuration)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the monitor is told the music is paused by us once as it pauses, and once more as it resumes")
    func tellsPausedByUs() async {
        let player = MockMusicPlayer()
        let told = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPausedByUsChange: { told.append($0) })

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("com.apple.Safari", playing: true) // still paused
        await arbiter.sourceChanged("com.apple.Safari", playing: false)
        #expect(told.value == [true])

        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(told.value == [true, false])
    }

    /// What the volume leveler is asked through two pauses for Viewer and their
    /// resumes, then monitoring's stop, with Level the volume `levels` (turned
    /// off before the stop when `turnsOff`) and the monitor's `offset`; and
    /// how many times the music was played.
    private func levelingLog(levels: Bool, offset: Float?, turnsOff: Bool = false) async -> (log: [String], plays: Int) {
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = levels
        let player = MockMusicPlayer()
        let leveler = RecordingVolumeLeveler()
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { offset })
        for plays in 1...2 {
            await arbiter.sourceChanged("org.example.viewer", playing: true)
            await arbiter.sourceChanged("org.example.viewer", playing: false)
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

    /// Lowered before each resume, and put back once the music is paused for the next app.
    private static var levelingCycle: [String] {
        ["lower -6.0", "restore over \(AppConfiguration.testing.fadeOutDuration)", "lower -6.0"]
    }

    @Test("with Level the volume on, the volume is lowered by the monitor's offset before each resume, put back once the music is paused and as monitoring stops")
    func levelsMusic() async {
        let run = await levelingLog(levels: true, offset: -6)
        #expect(run.log == Self.levelingCycle + ["restore now"] && run.plays == 2)
    }

    @Test("with Level the volume on, a pause that fails keeps the Mac's volume lowered: the music plays on at it, as it was")
    func failedPauseKeepsLevel() async {
        let player = MockMusicPlayer()
        let leveler = RecordingVolumeLeveler()
        let arbiter = makeLevelingArbiter(player, leveler: leveler)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false) // resumed, lowered 6 dB
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await player.setFailPause(StubError.failed)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitUntilIdle()
        #expect(await player.state == .playing)
        #expect(leveler.log == ["lower -6.0"])
    }

    /// How the music is muted in place of a pause, for `mutedPauseRestoresLevel`.
    enum MuteInPlaceOfPause: CaseIterable {
        case pauseFailed, playsWhileSaidPaused
    }

    @Test("with Level the volume on, a pause muted instead puts the Mac's volume back at once, as a pause does",
          arguments: MuteInPlaceOfPause.allCases)
    func mutedPauseRestoresLevel(way: MuteInPlaceOfPause) async {
        let player = MockMusicPlayer()
        let leveler = RecordingVolumeLeveler()
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        let mute = FakeMute()
        let arbiter = PlaybackArbiter(player: way == .pauseFailed ? player : MockMutingMusicPlayer(player),
                                      configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 },
                                      playerMute: way == .pauseFailed ? mute : nil)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false) // resumed, lowered 6 dB
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        switch way {
        case .pauseFailed: await player.setFailPause(StubError.failed)
        case .playsWhileSaidPaused:
            await player.setState(.paused)
            await player.setPlaysAnyway(true)
        }
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitUntilIdle()
        switch way {
        case .pauseFailed: #expect(mute.muteCount == 1)
        case .playsWhileSaidPaused: #expect(await player.commandLog.last == "mute")
        }
        #expect(leveler.log == ["lower -6.0", "restore now"])
    }

    @Test("turning Level the volume off puts back whatever is lowered, leaving monitoring's stop nothing of its own to put back")
    func levelingTurnedOff() async {
        let run = await levelingLog(levels: true, offset: -6, turnsOff: true)
        #expect(run.log == Self.levelingCycle + ["restore now (any)"] && run.plays == 2)
    }

    @Test("with Level the volume on, the Mac's volume isn't lowered when the apps weren't quieter than the music")
    func levelingWithoutOffset() async {
        let run = await levelingLog(levels: true, offset: nil)
        #expect(run.log.isEmpty && run.plays == 2)
    }

    @Test("with Level the volume off, the Mac's volume is never lowered")
    func levelingOff() async {
        let run = await levelingLog(levels: false, offset: -6)
        #expect(run.log.isEmpty && run.plays == 2)
    }

    @Test("the volume lowered by another monitoring (the app's one leveler) is never put back by this one's pause or stop")
    func levelingOnlyItsOwn() async {
        let leveler = RecordingVolumeLeveler()
        let other = leveler.lower(by: -4) // the player chosen now, as it resumed
        let player = MockMusicPlayer()
        let arbiter = makeLevelingArbiter(player, leveler: leveler)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await arbiter.sourceChanged("org.example.viewer", playing: true)
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

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.setUnansweredStateQueries(1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
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

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
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

    @Test("a resume the player never answers is given up and said so; Try Again resumes it; an app starting or the player answering ends it")
    func givenUpResumeSaidAndRetried() async {
        let player = MockMusicPlayer(), scheduler = ManualDebounceScheduler(), failures = Locked<[MusicPlayerError?]>([])
        let pausedByUs = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: statuses(resumeFailure: { failures.append($0) }),
                                      onPausedByUsChange: { pausedByUs.append($0) })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { failures.value == [.playerNotResponding] }
        #expect(await arbiter.pausedByUs == false)

        await arbiter.retryResume() // it answers now: paused, so it's played
        await TestWait.until { await player.playCallCount == 1 }
        #expect(failures.value == [.playerNotResponding, nil])
        // AutoHush's pause again while it tries (the monitor told), over once played.
        #expect(pausedByUs.value == [true, false, true, false])

        await arbiter.retryResume() // nothing to try again
        #expect(failures.value == [.playerNotResponding, nil])
    }

    @Test("a given-up resume is over once another app starts, or the player says how it is")
    func givenUpResumeEnds() async {
        for byApp in [true, false] {
            let player = MockMusicPlayer(), scheduler = ManualDebounceScheduler(), failures = Locked<[MusicPlayerError?]>([])
            let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                          onStatusUpdate: statuses(resumeFailure: { failures.append($0) }))
            await arbiter.sourceChanged("org.example.viewer", playing: true)
            await arbiter.waitForPause()
            await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
            await arbiter.sourceChanged("org.example.viewer", playing: false)
            for attempt in 1...PlaybackArbiter.resumeRetries {
                await TestWait.until { scheduler.scheduledDelays.count == attempt }
                await scheduler.completeNext()
            }
            await TestWait.until { failures.value.count == 1 }
            if byApp {
                await arbiter.sourceChanged("com.apple.Safari", playing: true)
            } else {
                await arbiter.handlePlayerStateChange(.playing)
            }
            #expect(failures.value == [.playerNotResponding, nil])
            await arbiter.waitUntilIdle()
        }
    }

    @Test("a resume whose play keeps failing is given up after its tries and said so")
    func failedPlaySaid() async {
        let player = MockMusicPlayer(failPlayWith: MusicPlayerError.playerCommandFailed(.pressIgnored))
        let scheduler = ManualDebounceScheduler(), failures = Locked<[MusicPlayerError?]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: statuses(resumeFailure: { failures.append($0) }))
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { failures.value == [.playerCommandFailed(.pressIgnored)] }
    }

    @Test("a given-up resume ends AutoHush's pause as it's said, and a play failing on its last try while an app starts says nothing")
    func givenUpResumeDetails() async {
        let player = MockMusicPlayer(), scheduler = ManualDebounceScheduler(), byUs = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onPausedByUsChange: { byUs.append($0) })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { byUs.value.last == false }

        let failing = MockMusicPlayer(failPlayWith: MusicPlayerError.playerCommandFailed(.pressIgnored))
        let failures = Locked<[MusicPlayerError?]>([]), other = ManualDebounceScheduler()
        let second = PlaybackArbiter(player: failing, configuration: .testing, debounceScheduler: other,
                                     onStatusUpdate: statuses(resumeFailure: { failures.append($0) }))
        await failing.setBeforePlay {
            if await failing.playCallCount == PlaybackArbiter.resumeRetries + 1 {
                await second.sourceChanged("com.apple.Safari", playing: true) // an app starts meanwhile
            }
        }
        await second.sourceChanged("org.example.viewer", playing: true)
        await second.waitForPause()
        await second.sourceChanged("org.example.viewer", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { other.scheduledDelays.count == attempt }
            await other.completeNext()
        }
        await TestWait.until { await failing.playCallCount == PlaybackArbiter.resumeRetries + 1 }
        await second.waitUntilIdle()
        #expect(!failures.value.contains(.playerCommandFailed(.pressIgnored)))
    }

    @Test("Try Again while an app plays again (Auto-Pause back on) doesn't resume")
    func retryResumeWhileAppPlays() async {
        let player = MockMusicPlayer(), scheduler = ManualDebounceScheduler(), failures = Locked<[MusicPlayerError?]>([])
        let published = LastPublished()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler,
                                      onStatusUpdate: statuses(playback: { published.set($0) }, resumeFailure: { failures.append($0) }))
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitForPause()
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.setAutoPauseEnabled(false) // resumed at once, the app still playing
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { failures.value == [.playerNotResponding] }
        await arbiter.setAutoPauseEnabled(true) // its pause waits for the app to be measured again
        await arbiter.retryResume()
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(published.state != .pausedByMonitor) // no pause held for it: the app's pause comes as usual
        #expect(failures.value == [.playerNotResponding, nil])
    }

    @Test("a resume whose command doesn't take is tried again")
    func retriesFailedResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.example.viewer", playing: false)
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

        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await TestWait.until { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await TestWait.until { await player.playCallCount == PlaybackArbiter.resumeRetries + 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == PlaybackArbiter.resumeRetries + 1)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries)
    }
}
