import Foundation
import os
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlaybackArbiter")
struct PlaybackArbiterTests {

    // MARK: - Helpers

    /// Waits until `condition` holds, for work that hops between actors.
    private func waitUntil(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () async -> Bool) async {
        await TestWait.until(sourceLocation: sourceLocation, condition)
    }

    /// For a test that holds the arbiter's work at a gate: gives the work
    /// that isn't held time to hop between actors before checking what
    /// happened, or that nothing more did. Elsewhere `waitUntilIdle()`
    /// waits exactly as long as that work.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(50))
    }

    private func makeArbiter(
        player: MockMusicPlayer = MockMusicPlayer(),
        configuration: AppConfiguration = .testing,
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler()
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler)
    }

    // MARK: - Filtering: excluded sources must not trigger pause

    @Test("the player's own audio and system audio daemons never pause it", arguments: [
        TestPlayer.bundleID,
        "com.apple.coreaudiod",
        "com.apple.audio.SandboxHelper",
        "com.apple.audio.UISoundsServer",
    ])
    func ignoresOwnAndSystemAudio(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    // MARK: - Pause behaviour

    /// Any other app alike: which apps count is AppConfiguration's (`isMediaSource`).
    @Test("pauses the player when another app starts playing", arguments: [
        "org.videolan.vlc",
        "com.example.somerandomplayer", // an app AutoHush knows nothing about
    ])
    func pausesForAnotherApp(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)

        #expect(await player.pauseCallCount == 1)
        #expect(await player.state == .paused)
    }

    @Test("does not pause the player when it is already paused")
    func doesNotPauseAlreadyPaused() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    @Test("a player heard while it says it's paused (a web app's ad) is muted, and played again when the other app stops")
    func mutesPlayerHeardWhilePaused() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.commandLog == ["mute"])
        #expect(await player.pauseCallCount == 0)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "play"])
    }

    @Test("a paused player that is silent is left alone, and not played afterwards")
    func leavesSilentPausedPlayer() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog.isEmpty)
    }

    @Test("a player that isn't playing on this Mac isn't asked to mute, nor one that can't mute")
    func doesNotMuteRemotePlayer() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let plain = makeArbiter(player: player)
        await plain.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 0)

        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())
        await arbiter.handleLocalPlaybackChange(false)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 0)
        #expect(await player.commandLog.isEmpty)
    }

    @Test("does not issue duplicate pause calls for repeated start events from the same source")
    func doesNotDuplicatePauseCalls() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
    }

    @Test("a pause that throws is a failed press, unless the player's controls are still being learned (a web app)",
          arguments: [false, true])
    func pauseErrorIsTolerated(stillLearning: Bool) async {
        let player = MockMusicPlayer(failPauseWith: stillLearning ? MusicPlayerError.stillLearning : StubError.failed)
        let states = ValuesLog<PlaybackState>()
        let failures = ValuesLog<MusicPlayerError?>()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.record($0) },
                                      onPauseFailure: { failures.record($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
        if stillLearning {
            #expect(failures.values.isEmpty)
            #expect(!states.values.contains(.pauseFailed))
        } else {
            #expect(failures.values == [.playerCommandFailed(.pressFailed)]) // an error of no kind AutoHush knows
            #expect(states.values.last == .pauseFailed)
        }
    }

    @Test("a pause that fails while another app plays says why, until the app stops")
    func failedPauseReported() async {
        let player = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.buttonDisabled))
        let states = OSAllocatedUnfairLock<[PlaybackState]>(initialState: [])
        let failures = OSAllocatedUnfairLock<[MusicPlayerError?]>(initialState: [])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { state in states.withLock { $0.append(state) } },
                                      onPauseFailure: { error in failures.withLock { $0.append(error) } })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(states.withLock { $0.last } == .pauseFailed)
        #expect(failures.withLock { $0 } == [.playerCommandFailed(.buttonDisabled)])

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { states.withLock { $0.last } == .musicPlaying }
        #expect(states.withLock { $0.last } == .musicPlaying)
        #expect(failures.withLock { $0 } == [.playerCommandFailed(.buttonDisabled), nil])
    }

    /// What ends a failed pause, for `failedPauseOver`.
    enum FailedPauseEnd: CaseIterable {
        case laterPauseWorks, userPauses, playsElsewhere, autoPauseOff, macSleeps
    }

    @Test("a failed pause is over once a later one works, the user pauses the music, it plays on another device, Auto-Pause goes off or the Mac sleeps",
          arguments: FailedPauseEnd.allCases)
    func failedPauseOver(end: FailedPauseEnd) async {
        let player = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.pressFailed))
        let failures = ValuesLog<MusicPlayerError?>()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPauseFailure: { failures.record($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        switch end {
        case .laterPauseWorks:
            await player.setFailPause(nil)
            await arbiter.sourceChanged("com.apple.Safari", playing: true) // a second app: this pause works
            #expect(await player.pauseCallCount == 2)
        case .userPauses: await arbiter.handlePlayerStateChange(.paused)
        case .playsElsewhere: await arbiter.handleLocalPlaybackChange(false)
        case .autoPauseOff: await arbiter.setAutoPauseEnabled(false)
        case .macSleeps: await arbiter.setAsleep(true)
        }
        #expect(failures.values == [.playerCommandFailed(.pressFailed), nil])
    }

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
        await waitUntil { await player.playCallCount == 1 }
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
            if !(staysPaused && call != nil) { await waitUntil { await player.playCallCount == 1 } }
            await arbiter.waitUntilIdle()
            return await player.playCallCount
        }
        #expect(await run(staysPaused: true, call: "us.zoom.xos") == 0)
        #expect(await run(staysPaused: true, call: "us.zoom.xos", callFirst: true) == 0)
        #expect(await run(staysPaused: true, call: nil) == 1)
        #expect(await run(staysPaused: false, call: "us.zoom.xos") == 1)
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
                await waitUntil { await player.playCallCount == plays }
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
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        let leveler = RecordingVolumeLeveler()
        let other = leveler.lower(by: -4) // the player chosen now, as it resumed
        let player = MockMusicPlayer()
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
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
        await waitUntil { scheduler.scheduledDelays.count == 1 } // the retry, a second later
        #expect(await player.playCallCount == 0)

        await scheduler.completeNext()
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        let queries = pauseQueries + PlaybackArbiter.resumeRetries + 1 // then the resume's, and the retries'
        await waitUntil { await player.stateQueryCount >= queries }
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
        await waitUntil { scheduler.scheduledDelays.count == 1 } // the retry, a second later
        #expect(await player.playCallCount == 1)

        await player.setFailPlay(nil)
        await scheduler.completeNext()
        await waitUntil { await player.playCallCount == 2 }
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
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await waitUntil { await player.playCallCount == PlaybackArbiter.resumeRetries + 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == PlaybackArbiter.resumeRetries + 1)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries)
    }

    // MARK: - Sleep

    @Test("music paused when the Mac goes to sleep stays paused after it wakes")
    func pauseForgottenInSleep() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: true)
        #expect(await player.pauseCallCount == 1)
        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: false) // its sound stops as the Mac falls asleep
        await arbiter.setAsleep(false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty)
        #expect(await player.state == .paused)
    }

    @Test("a sleep that arrives after a later wake is ignored")
    func lateSleepIgnored() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(false, change: 2) // the wake, told second, arrives first
        await arbiter.setAsleep(true, change: 1)  // the sleep, told first, arrives late
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 1) // awake: it pauses
    }

    @Test("a pause handed over while the Mac sleeps is forgotten too")
    func handoverForgottenInSleep() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(true)
        await arbiter.takeOverPause()
        await arbiter.setAsleep(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("nothing is paused while the Mac sleeps; an app still playing once it's awake pauses the music")
    func noPauseInSleep() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 0)

        await arbiter.setAsleep(false)
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("a mute in place of a pause is forgotten once the Mac is awake, and not played again")
    func muteForgottenAfterSleep() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.commandLog == ["mute"])
        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        #expect(await player.commandLog == ["mute"]) // told once awake, when it can act
        await arbiter.setAsleep(false)
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "forgetPause"])
    }

    @Test("a pause that ends after the Mac went to sleep is forgotten too: no resume once it's awake")
    func pauseFinishingInSleepForgotten() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let fading = Gate()
        let started = Gate()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await started.open(); await fading.wait() })

        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: true)
        await started.wait() // the fade-out is under way
        await arbiter.setAsleep(true)
        await fading.open()
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 1)
        await arbiter.setAsleep(false)
        // Its sound stopped as the Mac fell asleep; the monitor reports it once awake.
        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }

    @Test("a mute that comes after the Mac went to sleep is forgotten once it's awake")
    func muteFinishingInSleepForgotten() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let muting = Gate()
        let started = Gate()
        let arbiter = PlaybackArbiter(player: SlowMutingPlayer(MockMutingMusicPlayer(player), started: started, gate: muting),
                                      configuration: .testing, debounceScheduler: ManualDebounceScheduler())

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await started.wait() // it's being listened to
        await arbiter.setAsleep(true)
        await muting.open()
        await arbiter.waitForPause()
        #expect(await player.commandLog == ["mute"])
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.setAsleep(false)
        await waitUntil { await player.commandLog.count >= 2 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "forgetPause"])
    }

    // MARK: - Held resumes (Add an App's check)

    @Test("while resumes are held, music paused before the hold or during it stays paused in the other app's gaps; released, it resumes",
          arguments: [true, false])
    func heldResumes(pausedBeforeHold: Bool) async {
        let player = MockMusicPlayer()
        let states = ValuesLog<PlaybackState>()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.record($0) })

        if pausedBeforeHold { await arbiter.sourceChanged("org.videolan.vlc", playing: true) }
        await arbiter.holdResumes(true)
        if !pausedBeforeHold { await arbiter.sourceChanged("org.videolan.vlc", playing: true) }
        for _ in 1...2 { // the check's gaps
            await arbiter.sourceChanged("org.videolan.vlc", playing: false)
            await arbiter.waitUntilIdle()
            await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        }
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(await player.playCallCount == 0)
        #expect(states.values.last == .pausedByMonitor) // still ours: handed over should AutoHush quit

        await arbiter.holdResumes(false)
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.state == .playing)
    }

    @Test("an arbiter started with resumes held takes a pause over, and resumes it only once released")
    func startedHeld() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: scheduler, resumesHeld: true)

        #expect(await arbiter.takeOverPause())
        await scheduler.completeNext() // no app turned up
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)

        await arbiter.holdResumes(false)
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.state == .playing)
    }

    @Test("fades the music out before pausing and back in after resuming")
    func fadesAroundPauseAndResume() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(), fadeSleep: { _ in })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 1)
        #expect(await player.volumeHistory.contains(0))
        #expect(await player.volumeLevel == 60) // set back while paused

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await waitUntil { await player.volumeLevel == 60 }
        #expect(await player.commandLog.contains("volume 0"))
        #expect(await player.volumeLevel == 60)
    }

    @Test("the fade-in after a resume is not rushed by a cancelled task")
    func fadeInIsNotRushed() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let rushedSteps = Counter()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in if Task.isCancelled { await rushedSteps.increment() } })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await waitUntil { await player.volumeLevel == 60 }
        #expect(await rushedSteps.value == 0)
    }

    @Test("waiting for the resume returns once the music has faded back in, and at once with none under way")
    func waitForResumeWaitsForFadeIn() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let fadeInStarted = Gate()
        let fadingIn = Gate()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in
                                          // Only the fade-in, once played, is held.
                                          guard await player.playCallCount > 0 else { return }
                                          await fadeInStarted.open()
                                          await fadingIn.wait()
                                      })
        await arbiter.waitForResume() // none under way

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await fadeInStarted.wait()
        let waitsOver = Counter()
        Task {
            await arbiter.waitForResume()
            await waitsOver.increment()
        }
        await settle()
        #expect(await waitsOver.value == 0) // still fading in
        #expect((await player.volumeLevel ?? 0) < 60)

        await fadingIn.open()
        await waitUntil { await waitsOver.value == 1 }
        #expect(await player.volumeLevel == 60)
    }

    @Test("an app that stops during the fade-out leaves the music playing")
    func stopDuringFadeOut() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) // the fade-out runs on its own
        await waitUntil { await steps.count == 2 } // the fade-out has begun, held
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await steps.letGo(2)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("an app that starts while the music comes back up after a cancelled fade-out still pauses it")
    func restartDuringComeback() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        // Called off at its second step, the fade-out comes back up in two: steps 3 and 4.
        let steps = FadeSteps(holdingAt: 2, 4)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await steps.count == 2 }
        let calledOff = await player.volumeLevel ?? 0
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false) // music comes back up
        await steps.letGo(2)
        await waitUntil { await steps.count == 4 }
        #expect(await (player.volumeLevel ?? 0) > calledOff) // partway up
        await arbiter.handleSourceChange(sourceID: "com.google.Chrome", isPlaying: true) // and another app starts
        await steps.letGo(4)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 1)
    }

    @Test("music paused just as the other app stopped, or Auto-Pause went off, is still resumed", arguments: [false, true])
    func everyAppStopsWhilePausing(autoPauseGoesOff: Bool) async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let restore = Gate()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { if $0 == VolumeFader.restoreDelay { await restore.wait() } })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await player.pauseCallCount == 1 } // paused, volume not yet set back
        if autoPauseGoesOff {
            await arbiter.setAutoPauseEnabled(false) // too late to call the pause off
        } else {
            await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        }
        await settle() // a resume now, before the pause has finished, finds nothing to do
        #expect(await player.playCallCount == 0)
        await restore.open()
        await arbiter.waitForPause()

        await waitUntil { await player.playCallCount == 1 }
        await waitUntil { await player.volumeLevel == 60 }
        #expect(await player.playCallCount == 1)
        #expect(await player.volumeLevel == 60)
    }

    @Test("music the user pauses during the fade-out is not taken over, and not resumed later")
    func userPausesDuringFadeOut() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await steps.count == 2 } // the fade-out has begun, held
        await player.overrideState(.paused) // the user pauses the player mid-fade
        await steps.letGo(2)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("does not resume the player when it did not pause it")
    func doesNotResumeIfNotPausedByUs() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
    }

    @Test("does not resume while another foreign source is still active")
    func doesNotResumeWithActiveSource() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("com.colliderli.iina", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
    }

    @Test("an app that starts while the resume checks on the player calls the resume off")
    func cancelsPendingResumeOnNewSource() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)
        let answer = Gate()

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await waitUntil { await player.stateQueryCount > pauseQueries } // the resume is asking the player
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: true)
        await answer.open()
        await arbiter.waitForPause()
        await settle()

        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }

    // MARK: - PlaybackState reporting

    /// Delivers PlaybackState values via AsyncStream so tests can await them
    /// without any Task-hop race between the synchronous callback and the assertion.
    private final class StateStream: @unchecked Sendable {
        private let continuation: AsyncStream<PlaybackState>.Continuation
        let stream: AsyncStream<PlaybackState>

        init() {
            var cont: AsyncStream<PlaybackState>.Continuation!
            stream = AsyncStream { cont = $0 }
            continuation = cont
        }

        func yield(_ state: PlaybackState) { continuation.yield(state) }
    }

    private func makeArbiterWithStream(
        player: MockMusicPlayer = MockMusicPlayer(),
        stream: StateStream
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: player,
            configuration: AppConfiguration(),
            debounceScheduler: ManualDebounceScheduler(),
            onPlaybackStateChange: { state in stream.yield(state) }
        )
    }

    /// Awaits the next value from the stream, or `nil` after `TestWait.limit`.
    private func nextState(from stream: AsyncStream<PlaybackState>) async -> PlaybackState? {
        await withTaskGroup(of: PlaybackState?.self) { group in
            group.addTask {
                for await state in stream { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: TestWait.limit)
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    @Test("a resume publishes that the music plays, not the paused state its check found")
    func resumePublishesMusicPlaying() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
    }

    @Test("publishes pausedByMonitor while a foreign source is active")
    func publishesPausedByMonitorWhileSourceActive() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        let state = await nextState(from: stateStream.stream)
        #expect(state == .pausedByMonitor)
    }

    @Test("refreshPlaybackState publishes musicPlaying when the player is playing")
    func refreshPublishesPlayerPlaying() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.refreshPlaybackState()

        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicPlaying)
    }

    @Test("refreshPlaybackState publishes musicIdle when the player is paused")
    func refreshPublishesPlayerIdle() async {
        let player = MockMusicPlayer(state: .paused)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.refreshPlaybackState()

        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicIdle)
    }

    // MARK: - Player state notifications / user-intent protection

    @Test("user resuming the player while a source plays clears pausedByUs and publishes musicPlaying")
    func playerPlayingNotificationClearsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream)  // drain .pausedByMonitor

        // User resumes the player; the player reports that it plays.
        await player.overrideState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        // The player plays alongside the other app; we no longer hold it paused.
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)

        // When the source stops, the arbiter must not touch the player.
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the player quitting clears pausedByUs so nothing is resumed later")
    func playerNotRunningClearsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await player.overrideState(.notRunning)
        await arbiter.handlePlayerStateChange(.notRunning)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the player stopping clears pausedByUs so nothing is resumed later")
    func playerStoppedClearsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await player.overrideState(.stopped)
        await arbiter.handlePlayerStateChange(.stopped)
        _ = await nextState(from: stateStream.stream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the Paused notification caused by our own pause keeps pausedByUs")
    func ownPauseNotificationKeepsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 1)
    }

    @Test("a stale report that the player plays doesn't end our pause while it's still paused")
    func staleReportKeepsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        #expect(await player.state == .paused)
        // Right after our pause, the player reports its previous state, then the new one.
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }

        #expect(await player.playCallCount == 1)
    }

    @Test("when the player doesn't answer, a report that it plays ends our pause")
    func unansweredReportEndsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        await player.setUnansweredStateQueries(1)
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
    }

    @Test("an unknown player state is ignored and the resume still happens")
    func unknownStateIsIgnored() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handlePlayerStateChange(.unknown)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 1)
    }

    @Test("status updates from notifications do not query the player through Apple events")
    func notificationsDoNotQueryPlayer() async {
        let player = MockMusicPlayer(state: .paused)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handlePlayerStateChange(.paused)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        #expect(await player.stateQueryCount == 0)
    }

    // MARK: - The player playing on another device

    @Test("does not pause the player while it plays on another device")
    func doesNotPauseRemotePlayback() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
        #expect(await player.stateQueryCount == 0)
    }

    @Test("pauses again once playback is back on this Mac")
    func pausesAfterPlaybackReturns() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.handleLocalPlaybackChange(true)
        await arbiter.sourceChanged("com.apple.Safari", playing: true)

        #expect(await player.pauseCallCount == 1)
    }

    @Test("publishes playingElsewhere while the player plays on another device")
    func publishesPlayingElsewhere() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handleLocalPlaybackChange(false)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
    }

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
        await waitUntil { await player.playCallCount == 1 } // the resume runs on its own

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
        await waitUntil { await player.playCallCount == 1 }
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
        await waitUntil { scheduler.scheduledDelays.count == 1 } // the retry is scheduled
        await arbiter.sourceChanged("com.google.Chrome", playing: true)
        await scheduler.completeNext()

        await waitUntil { await player.playCallCount == 1 }
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
        await waitUntil { await player.pauseCallCount == 1 }
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

    // MARK: - Taking over a pause after an update

    @Test("a pause taken over from before the restart ends when no app is found playing, once the longest start the monitor applies (AntiDot mode's) and a margin have passed",
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
        await waitUntil { await player.playCallCount == 1 }
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
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
        #expect(scheduler.scheduledDelays.isEmpty)
    }

    // MARK: - When audio levels are needed (recording indicator)

    private final class ValuesLog<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Value] = []
        var values: [Value] { lock.withLock { _values } }
        func record(_ value: Value) { lock.withLock { _values.append(value) } }
    }

    @Test("levels are needed only while the player plays here or is paused by us, with auto-pause on")
    func audioLevelsNeeded() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let log = ValuesLog<Bool>()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(), debounceScheduler: scheduler,
            onAudioLevelsNeededChange: { log.record($0) }
        )

        await arbiter.refreshPlaybackState()                       // The player paused by the user
        await arbiter.handlePlayerStateChange(.playing)           // plays here
        await player.overrideState(.playing)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true) // we pause it: still needed
        await arbiter.setAutoPauseEnabled(false)                   // resumed and off: not needed
        await waitUntil { await player.playCallCount == 1 }
        await arbiter.setAutoPauseEnabled(true)                    // on again; VLC is still active, so the player is paused again
        await arbiter.waitForPause()
        await arbiter.handlePlayerStateChange(.stopped)           // the user takes over

        #expect(log.values == [false, true, false, true, false])
    }

    @Test("levels are not needed while the player plays on another device")
    func audioLevelsNotNeededElsewhere() async {
        let log = ValuesLog<Bool>()
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .playing), configuration: AppConfiguration(),
            onAudioLevelsNeededChange: { log.record($0) }
        )
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.handleLocalPlaybackChange(false)
        #expect(log.values == [true, false])
    }

    // MARK: - Shutdown

    @Test("shutdown calls off a resume under way")
    func shutdownCancelsPendingResume() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)
        let answer = Gate()

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await waitUntil { await player.stateQueryCount > pauseQueries } // the resume is asking the player
        await arbiter.shutdown()
        await answer.open()
        await settle()

        #expect(await player.playCallCount == 0)
    }

    @Test("a shut-down arbiter ignores new sources")
    func shutdownIgnoresNewSources() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.shutdown()
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    // MARK: - Resume edge cases

    @Test("resume is skipped when the live check finds the player stopped")
    func resumeSkippedWhenFoundStopped() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        // Source starts → arbiter pauses the player.
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream)  // drain .pausedByMonitor

        // The user stops the player, and no notification says so.
        await player.overrideState(.stopped)

        // Source stops → the resume asks the player first, and must NOT call play().
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicIdle)
        // Confirm play() was never called: the player should remain .stopped.
        let finalState = await player.playerState()
        #expect(finalState == .stopped)
    }

    @Test("resume is skipped when the live check finds the player not running")
    func resumeSkippedWhenFoundNotRunning() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        // The user quits the player, and no notification says so.
        await player.overrideState(.notRunning)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        let playCount = await player.playCallCount
        #expect(playCount == 0)
        let finalState = await player.playerState()
        #expect(finalState == .notRunning)
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
        await waitUntil { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 1)
    }

    // MARK: - A pause made by an app as it starts (VLC pauses Spotify and Music)

    /// An arbiter on the test's clock, knowing its player plays.
    private func makeClockedArbiter(
        player: MockMusicPlayer,
        clock: ManualClock,
        configuration: AppConfiguration = .testing,
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler(),
        autoPauseEnabled: Bool = true,
        fadeSleep: @escaping VolumeFader.Sleep = { _ in },
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in }
    ) async -> PlaybackArbiter {
        let arbiter = PlaybackArbiter(
            player: player, configuration: configuration, debounceScheduler: scheduler, fadeSleep: fadeSleep,
            clock: { clock.now }, autoPauseEnabled: autoPauseEnabled,
            onPlaybackStateChange: onPlaybackStateChange, onAudioLevelsNeededChange: onAudioLevelsNeededChange
        )
        await arbiter.refreshPlaybackState()
        return arbiter
    }

    /// Something other than AutoHush pauses the player, and its observer says so.
    private func pausedElsewhere(_ player: MockMusicPlayer, _ arbiter: PlaybackArbiter) async {
        await player.overrideState(.paused)
        await arbiter.handlePlayerStateChange(.paused)
    }

    @Test("music another app pauses as it starts comes back when that app stops, with no pause of ours")
    func takesOverPauseOfStartingApp() async {
        let player = MockMusicPlayer()
        let clock = ManualClock()
        let states = ValuesLog<PlaybackState>()
        let needs = ValuesLog<Bool>()
        let arbiter = await makeClockedArbiter(player: player, clock: clock,
                                               onPlaybackStateChange: { states.record($0) },
                                               onAudioLevelsNeededChange: { needs.record($0) })
        let heard = clock.now
        clock.advance(by: 0.3)
        await pausedElsewhere(player, arbiter) // VLC pauses it
        clock.advance(by: 0.2)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true, heardSince: heard)

        #expect(await player.pauseCallCount == 0)
        #expect(states.values.last == .pausedByMonitor)
        #expect(needs.values == [true, false, true]) // levels kept to hear VLC stop

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await waitUntil { await player.playCallCount == 1 }
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
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
        if isTakenOver { await waitUntil { await player.playCallCount == 1 } } else { await arbiter.waitUntilIdle() }

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
        await waitUntil { await player.stateQueryCount == 2 } // after the one at start-up
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
        await waitUntil { await steps.count == 2 } // the fade-out has begun, held
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

        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
        await waitUntil { await player.playCallCount == 1 }
        #expect(await player.playCallCount == 1)
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
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let leveler = RecordingVolumeLeveler()
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler,
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            #expect(!leveler.log.contains("restore now")) // tried again: still lowered
            await scheduler.completeNext()
        }
        await waitUntil { leveler.log.last == "restore now" }
        await arbiter.waitUntilIdle()
        #expect(leveler.log == Array(repeating: "lower -6.0", count: PlaybackArbiter.resumeRetries + 1) + ["restore now"])
        #expect(await player.playCallCount == PlaybackArbiter.resumeRetries + 1)
    }

    /// What happens to a resume that lowered the Mac's volume and failed,
    /// before it's tried again.
    enum BeforeRetry: String, CaseIterable, Sendable {
        case playerStopped, playerPlays, noAnswer, appStarts, userTookOver, staysPausedAfterCall, resumesHeld, macSleeps
    }

    @Test("with Level the volume on, a resume that lowered the Mac's volume, failed, and doesn't bring the music back at its retry puts the volume back at once; one whose music plays after all keeps it lowered for it",
          arguments: BeforeRetry.allCases)
    func levelingPutBackWithoutMusic(_ before: BeforeRetry) async {
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let leveler = RecordingVolumeLeveler()
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler,
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        let call = "us.zoom.xos"
        if before == .staysPausedAfterCall { await arbiter.handleCallChange(sourceID: call, inCall: true) }
        let app = before == .staysPausedAfterCall ? call : "org.videolan.vlc"
        await arbiter.sourceChanged(app, playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged(app, playing: false)
        await waitUntil { scheduler.scheduledDelays.count == 1 } // failed: tried again in a second
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
            await waitUntil { scheduler.scheduledDelays.count == 2 } // no answer: once more
            await scheduler.completeNext()
        case .appStarts:
            await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        case .userTookOver:
            await player.overrideState(.stopped)
            await arbiter.handlePlayerStateChange(.stopped)
            await scheduler.completeNext()
        case .staysPausedAfterCall:
            var staysPaused = configuration
            staysPaused.staysPausedAfterCalls = true // turned on meanwhile
            await arbiter.setConfiguration(staysPaused)
            await scheduler.completeNext()
        case .resumesHeld:
            await arbiter.holdResumes(true)
        case .macSleeps:
            await arbiter.setAsleep(true)
        }
        await arbiter.waitUntilIdle()

        #expect(leveler.log == (before == .playerPlays ? ["lower -6.0"] : ["lower -6.0", "restore now"]))
        #expect(await player.playCallCount == 1)
        await arbiter.shutdown()
    }
}

private extension PlaybackArbiter {
    /// Reports a source change, then waits for the pause it may start, so a
    /// test sees its outcome.
    func sourceChanged(_ sourceID: String, playing: Bool, heardSince: Date? = nil) async {
        await handleSourceChange(sourceID: sourceID, isPlaying: playing, heardSince: heardSince)
        await waitForPause()
    }
}

/// Records what the arbiter asks of the volume leveler. As the real one,
/// it lowers once until put back, and a put-back with another lowering's
/// token does nothing (it isn't logged).
private final class RecordingVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    private var lowered: UUID?
    var log: [String] { lock.withLock { _log } }

    func lower(by decibels: Float) -> UUID? {
        lock.withLock {
            _log.append("lower \(decibels)")
            guard lowered == nil else { return nil }
            lowered = UUID()
            return lowered
        }
    }

    func restore(over duration: TimeInterval, lowered token: UUID) {
        putBack(token, as: "restore over \(duration)")
    }

    func restoreNow(lowered token: UUID) {
        putBack(token, as: "restore now")
    }

    func restoreNow() {
        lock.withLock {
            _log.append("restore now (any)")
            lowered = nil
        }
    }

    private func putBack(_ token: UUID, as entry: String) {
        lock.withLock {
            guard token == lowered else { return }
            _log.append(entry)
            lowered = nil
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

/// A muting player whose check before muting waits for `gate`, saying so
/// on `started`: the Mac can go to sleep meanwhile.
private actor SlowMutingPlayer: MutingMusicPlayer {
    let wrapped: MockMutingMusicPlayer
    let started: Gate
    let gate: Gate

    init(_ wrapped: MockMutingMusicPlayer, started: Gate, gate: Gate) {
        self.wrapped = wrapped
        self.started = started
        self.gate = gate
    }

    nonisolated var bundleID: String { wrapped.bundleID }
    nonisolated var name: String { wrapped.name }
    nonisolated var stateReportDelay: TimeInterval { wrapped.stateReportDelay }
    nonisolated func allowTaps(_ allowed: Bool) { wrapped.allowTaps(allowed) }
    func muteIfPlayingAnyway() async -> Bool {
        await started.open()
        await gate.wait()
        return await wrapped.muteIfPlayingAnyway()
    }
    func forgetPause() async { await wrapped.forgetPause() }
    func verifyControlAccess() async throws { try await wrapped.verifyControlAccess() }
    func playerState() async -> PlayerState { await wrapped.playerState() }
    func pause() async throws { try await wrapped.pause() }
    func play() async throws { try await wrapped.play() }
    func volume() async -> Int? { await wrapped.volume() }
    func setVolume(_ volume: Int) async throws { try await wrapped.setVolume(volume) }

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }
}

/// Counts a fade's steps (each sleep before a volume change) and holds it
/// at the ones given until let go, so a test acts mid-fade, however busy the
/// machine.
private actor FadeSteps {
    private(set) var count = 0
    private var holds: [Int: Gate] = [:]

    init(holdingAt steps: Int...) {
        for step in steps { holds[step] = Gate() }
    }

    func step() async {
        count += 1
        await holds[count]?.wait()
    }

    func letGo(_ step: Int) async { await holds[step]?.open() }
}

/// Holds whoever waits on it until it is opened.
private actor Gate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
