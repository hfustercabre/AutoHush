import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Held resumes (Add an App's check)

    @Test("while resumes are held, music paused before the hold or during it stays paused in the other app's gaps; released, it resumes",
          arguments: [true, false])
    func heldResumes(pausedBeforeHold: Bool) async {
        let player = MockMusicPlayer()
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) })

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
        #expect(states.value.last == .pausedByMonitor) // still ours: handed over should AutoHush quit

        await arbiter.holdResumes(false)
        await TestWait.until { await player.playCallCount == 1 }
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
        await TestWait.until { await player.playCallCount == 1 }
        #expect(await player.state == .playing)
    }

    @Test("resumes held while a pause taken over waits for apps show the music paused by AutoHush at once, though no app plays")
    func holdShowsTakenOverPause() async {
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(state: .paused), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) })

        #expect(await arbiter.takeOverPause())
        #expect(states.value.last == .musicIdle) // no app plays, and its resume waits
        await arbiter.holdResumes(true)
        #expect(states.value.last == .pausedByMonitor)
    }

    @Test("fades the music out before pausing and back in after resuming: played from near silence, then up in steps")
    func fadesAroundPauseAndResume() async throws {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(), fadeSleep: { _ in })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 1)
        #expect(await player.volumeHistory.contains(0))
        #expect(await player.volumeLevel == 60) // set back while paused

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitForResume() // faded back in
        let log = await player.commandLog
        let play = try #require(log.lastIndex(of: "play"))
        #expect(log[play - 1] == "volume 0")
        let risen = log[(play + 1)...].compactMap { Int($0.replacingOccurrences(of: "volume ", with: "")) }
        #expect(risen.count > 2)
        #expect(zip(risen, risen.dropFirst()).allSatisfy { $0 < $1 })
        #expect(risen.last == 60)
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
        await TestWait.until { await player.playCallCount == 1 }
        await TestWait.until { await player.volumeLevel == 60 }
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
        #expect((await player.volumeLevel ?? 0) < 60) // fading in

        await fadingIn.open()
        await arbiter.waitForResume()
        #expect(await player.volumeLevel == 60) // returned only once faded back in
    }

    @Test("an app that stops during the fade-out leaves the music playing")
    func stopDuringFadeOut() async {
        let player = MockMusicPlayer()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await makeFadingArbiter(player, steps: steps)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) // the fade-out runs on its own
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await steps.letGo(2)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("monitoring that stops during the fade-out (AutoHush quits, or the player is switched) puts the music's volume back at once, and pauses nothing")
    func shutdownDuringFadeOut() async {
        let player = MockMusicPlayer()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await makeFadingArbiter(player, steps: steps)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
        #expect((await player.volumeLevel ?? 0) < 60)
        await arbiter.shutdown()
        #expect(await player.volumeLevel == 60)
        await steps.letGo(2)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("Auto-Pause turned off during the fade-out brings the music back up, without pausing it and playing it again")
    func autoPauseOffDuringFadeOut() async {
        let player = MockMusicPlayer()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await makeFadingArbiter(player, steps: steps)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
        await arbiter.setAutoPauseEnabled(false)
        await steps.letGo(2)
        await arbiter.waitUntilIdle()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.playCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("an app that starts while the music comes back up after a cancelled fade-out still pauses it")
    func restartDuringComeback() async {
        let player = MockMusicPlayer()
        // Called off at its second step, the fade-out comes back up in two: steps 3 and 4.
        let steps = FadeSteps(holdingAt: 2, 4)
        let arbiter = await makeFadingArbiter(player, steps: steps)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await TestWait.until { await steps.count == 2 }
        let calledOff = await player.volumeLevel ?? 0
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false) // music comes back up
        await steps.letGo(2)
        await TestWait.until { await steps.count == 4 }
        let partway = await player.volumeLevel ?? 0
        #expect(partway > calledOff) // partway up
        let mark = await player.commandLog.count
        await arbiter.handleSourceChange(sourceID: "com.google.Chrome", isPlaying: true) // and another app starts
        await steps.letGo(4)
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 1)
        // The way back up stops there: it fades out again from where it was.
        let fadeOut = await player.commandLog.dropFirst(mark).prefix { $0 != "pause" }
        #expect(fadeOut.allSatisfy { Int($0.dropFirst("volume ".count)).map { $0 <= partway } ?? true })
    }

    @Test("music paused just as the other app stopped, or Auto-Pause went off, is still resumed", arguments: [false, true])
    func everyAppStopsWhilePausing(autoPauseGoesOff: Bool) async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let restore = Gate()
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { if $0 == VolumeFader.restoreDelay { await restore.wait() } },
                                      onPlaybackStateChange: { states.append($0) })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await TestWait.until { await player.pauseCallCount == 1 } // paused, volume not yet set back
        let published = states.value.count
        if autoPauseGoesOff {
            await arbiter.setAutoPauseEnabled(false) // too late to call the pause off: nothing of ours to resume yet
        } else {
            await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
            // A resume now, before the pause has finished, finds nothing to do (and says so).
            await TestWait.until { states.value.count > published }
        }
        #expect(await player.playCallCount == 0)
        await restore.open()
        await arbiter.waitForPause()

        await TestWait.until { await player.playCallCount == 1 }
        await TestWait.until { await player.volumeLevel == 60 }
        #expect(await player.playCallCount == 1) // once only
    }

    @Test("music the user pauses during the fade-out is not taken over, and not resumed later")
    func userPausesDuringFadeOut() async {
        let player = MockMusicPlayer()
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await makeFadingArbiter(player, steps: steps)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await TestWait.until { await steps.count == 2 } // the fade-out has begun, held
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

    @Test("an app that starts while the resume checks on the player calls the resume off")
    func cancelsPendingResumeOnNewSource() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)
        let answer = Gate()

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await TestWait.until { await player.stateQueryCount > pauseQueries } // the resume is asking the player
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: true)
        await answer.open()
        await arbiter.waitUntilIdle() // the pause, and the resume it called off

        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
