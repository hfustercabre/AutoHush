import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlaybackArbiter")
struct PlaybackArbiterTests {

    // MARK: - Helpers

    /// Yields until `condition` holds (or about a second has passed), for
    /// work that hops between actors.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Gives work that hops between actors time to finish before checking
    /// what happened (or that nothing more did).
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

    @Test("pauses the player when another app starts playing", arguments: [
        "org.videolan.vlc",
        "com.example.somerandomplayer", // an app AutoHush knows nothing about
        "com.google.Chrome.helper",     // a browser's helper process
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.apple.QuickTimePlayerX",
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
        await settle()
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
        await settle()
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

    @Test("does not pause when the pause call itself throws")
    func pauseErrorIsTolerated() async {
        let player = MockMusicPlayer(failPauseWith: StubError.failed)
        let arbiter = makeArbiter(player: player)

        // Should not crash; error is swallowed gracefully
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
        #expect(await player.state == .playing) // state unchanged because pause threw
    }

    // MARK: - Resume behaviour

    @Test("resumes the player as soon as the other app stops", arguments: [
        "org.videolan.vlc",
        "com.google.Chrome.helper",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.apple.QuickTimePlayerX",
    ])
    func resumesAfterSourceStops(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)
        await arbiter.sourceChanged(sourceID, playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await settle()

        #expect(await player.state == .playing)
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
        await player.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await waitUntil { await player.stateQueryCount == PlaybackArbiter.resumeRetries + 2 } // the pause's, the resume's, the retries
        await settle()
        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries)
    }

    @Test("a resume whose command doesn't take is tried again")
    func retriesFailedResume() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed("the page didn't follow"))
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
        await player.setFailPlay(MusicPlayerError.playerCommandFailed("the page didn't follow"))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        for attempt in 1...PlaybackArbiter.resumeRetries {
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await waitUntil { await player.playCallCount == PlaybackArbiter.resumeRetries + 1 }
        await settle()
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
        await settle()
        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty)
        #expect(await player.state == .paused)
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
        await settle()
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
        await settle()
        #expect(await player.commandLog == ["mute", "forgetPause"])
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

    @Test("an app that stops during the fade-out leaves the music playing")
    func stopDuringFadeOut() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in try? await Task.sleep(for: .milliseconds(5)) })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) // the fade-out runs on its own
        await waitUntil { await !player.volumeHistory.isEmpty } // the fade-out has begun
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("an app that starts while the music comes back up after a cancelled fade-out still pauses it")
    func restartDuringComeback() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in try? await Task.sleep(for: .milliseconds(5)) })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await !player.volumeHistory.isEmpty }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false) // music comes back up
        await waitUntil { await (player.volumeLevel ?? 0) > 20 }
        await arbiter.sourceChanged("com.google.Chrome", playing: true) // and another app starts

        #expect(await player.pauseCallCount == 1)
    }

    @Test("music paused just as the other app stopped is still resumed")
    func everyAppStopsWhilePausing() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let restore = Gate()
        let arbiter = PlaybackArbiter(player: player, configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { if $0 == VolumeFader.restoreDelay { await restore.wait() } })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await player.pauseCallCount == 1 } // paused, volume not yet set back
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await settle() // the resume comes before the pause has finished, and finds nothing to do
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
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in try? await Task.sleep(for: .milliseconds(5)) })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await waitUntil { await !player.volumeHistory.isEmpty }
        await player.overrideState(.paused) // the user pauses the player mid-fade
        await arbiter.waitForPause()

        #expect(await player.pauseCallCount == 0)
        #expect(await player.volumeLevel == 60)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await settle()
        #expect(await player.playCallCount == 0)
    }

    @Test("does not resume the player when it did not pause it")
    func doesNotResumeIfNotPausedByUs() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await settle()

        #expect(await player.playCallCount == 0)
    }

    @Test("does not resume while another foreign source is still active")
    func doesNotResumeWithActiveSource() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("com.colliderli.iina", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await settle()

        #expect(await player.playCallCount == 0)
    }

    @Test("an app that starts while the resume checks on the player calls the resume off")
    func cancelsPendingResumeOnNewSource() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)
        let answer = Gate()

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await waitUntil { await player.stateQueryCount == 2 } // the pause's, then the resume's
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

    /// Awaits the next value from the stream with a short timeout.
    private func nextState(from stream: AsyncStream<PlaybackState>) async -> PlaybackState? {
        await withTaskGroup(of: PlaybackState?.self) { group in
            group.addTask {
                for await state in stream { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(500))
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    @Test("publishes musicPlaying immediately after resume without re-querying the player")
    func resumePublishesPlayerPlayingWithoutRaceCondition() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        // Drain the .pausedByMonitor event.
        _ = await nextState(from: stateStream.stream)

        // The player reports .paused when the resume asks (the race the fix closes).
        await player.overrideState(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)

        // Must be .musicPlaying — not .musicIdle — even though playerState() returns .paused.
        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicPlaying)
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
        await settle()
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
        await settle()
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
        await settle()
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
        await settle()

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
        await settle()

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
        await settle()

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
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(false)

        #expect(await player.playCallCount == 0)
    }

    @Test("turning auto-pause off just as the last app stops resumes the music once")
    func turningOffCancelsPendingResume() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.setAutoPauseEnabled(false)
        await waitUntil { await player.playCallCount == 1 }
        await settle()

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
        await settle()

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
        await settle()

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
        await settle()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("turning auto-pause back on with nothing playing does nothing")
    func turningOnIdleDoesNothing() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(), autoPauseEnabled: false)

        await arbiter.setAutoPauseEnabled(true)

        #expect(await player.pauseCallCount == 0)
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

    @Test("a pause taken over from before the restart ends when no app is found playing")
    func takenOverPauseResumes() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.takeOverPause()
        #expect(scheduler.scheduledDelays == [AppConfiguration.testing.sourceStartConfirmation + PlaybackArbiter.takeOverMargin])
        #expect(await player.playCallCount == 0)

        await scheduler.completeNext() // no app turned up
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
        await settle()
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

        await arbiter.takeOverPause()
        await settle()
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

    private final class NeedsLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Bool] = []
        var values: [Bool] { lock.withLock { _values } }
        func record(_ value: Bool) { lock.withLock { _values.append(value) } }
    }

    @Test("levels are needed only while the player plays here or is paused by us, with auto-pause on")
    func audioLevelsNeeded() async {
        let player = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let log = NeedsLog()
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
        let log = NeedsLog()
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
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await waitUntil { await player.stateQueryCount == 2 } // the resume is asking the player
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
        await settle()

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
        await settle()
        #expect(await player.playCallCount == 0) // IINA still plays

        await arbiter.sourceChanged("com.colliderli.iina", playing: false)
        await waitUntil { await player.playCallCount == 1 }
        await settle()
        #expect(await player.playCallCount == 1)
    }
}

private extension PlaybackArbiter {
    /// Reports a source change, then waits for the pause it may start, so a
    /// test sees its outcome.
    func sourceChanged(_ sourceID: String, playing: Bool) async {
        await handleSourceChange(sourceID: sourceID, isPlaying: playing)
        await waitForPause()
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
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
