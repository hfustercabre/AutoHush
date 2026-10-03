import Foundation
import Testing
@testable import AutoHush

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

    private func makeArbiter(
        spotify: MockMusicPlayer = MockMusicPlayer(),
        configuration: AppConfiguration = AppConfiguration(),
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler()
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: spotify, configuration: configuration, debounceScheduler: scheduler)
    }

    // MARK: - Filtering: excluded sources must not trigger pause

    @Test("ignores Spotify's own bundle ID")
    func ignoresSpotify() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.spotify.client", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
    }

    @Test("ignores system audio daemons")
    func ignoresSystemDaemons() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.apple.coreaudiod", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.apple.audio.SandboxHelper", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.apple.audio.UISoundsServer", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
    }

    // MARK: - Pause behaviour

    @Test("pauses Spotify when a foreign media source starts")
    func pausesForForeignSource() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
        #expect(await spotify.state == .paused)
    }

    @Test("pauses Spotify for an unknown app")
    func pausesForUnknownApp() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.example.somerandomplayer", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("pauses Spotify for a Chrome renderer helper")
    func pausesForChromeHelper() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.google.Chrome.helper", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("pauses Spotify when Safari starts playing")
    func pausesForSafari() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.apple.Safari", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("pauses Spotify when Firefox starts playing")
    func pausesForFirefox() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.mozilla.firefox", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("pauses Spotify when QuickTime Player starts playing")
    func pausesForQuickTimePlayer() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("does not pause Spotify that is already paused")
    func doesNotPauseAlreadyPaused() async {
        let spotify = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
    }

    @Test("does not issue duplicate pause calls for repeated start events from the same source")
    func doesNotDuplicatePauseCalls() async {
        let spotify = MockMusicPlayer()
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("does not pause when the pause call itself throws")
    func pauseErrorIsTolerated() async {
        let spotify = MockMusicPlayer(failPauseWith: StubError.failed)
        let arbiter = makeArbiter(spotify: spotify)

        // Should not crash; error is swallowed gracefully
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
        #expect(await spotify.state == .playing) // state unchanged because pause threw
    }

    // MARK: - Resume behaviour

    @Test("resumes Spotify after the foreign source stops and debounce completes")
    func resumesAfterSourceStops() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        // Yield until the actor-reentrant resumeIfStillPending finishes.
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.state == .playing)
        #expect(await spotify.playCallCount == 1)
    }

    @Test("retries the resume when Spotify does not answer, instead of giving up")
    func retriesUnansweredResume() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await spotify.setUnansweredStateQueries(1)
        await scheduler.completeNext()
        await waitUntil { scheduler.scheduledDelays.count == 2 } // the retry, a second later
        #expect(await spotify.playCallCount == 0)

        await scheduler.completeNext()
        await waitUntil { await spotify.playCallCount == 1 }
        #expect(await spotify.playCallCount == 1)
        #expect(scheduler.scheduledDelays == [AppConfiguration().debounceSeconds, PlaybackArbiter.resumeRetryDelay])
    }

    @Test("stops retrying once Spotify has not answered every retry")
    func givesUpAfterRetries() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await spotify.setUnansweredStateQueries(PlaybackArbiter.resumeRetries + 1)
        for attempt in 1...PlaybackArbiter.resumeRetries + 1 {
            await waitUntil { scheduler.scheduledDelays.count == attempt }
            await scheduler.completeNext()
        }
        await waitUntil { await spotify.stateQueryCount == PlaybackArbiter.resumeRetries + 2 }
        #expect(await spotify.playCallCount == 0)
        #expect(scheduler.scheduledDelays.count == PlaybackArbiter.resumeRetries + 1)
    }

    @Test("fades the music out before pausing and back in after resuming")
    func fadesAroundPauseAndResume() async {
        let spotify = MockMusicPlayer()
        await spotify.setVolumeLevel(60)
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(),
                                      debounceScheduler: scheduler, fadeSleep: { _ in })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        #expect(await spotify.pauseCallCount == 1)
        #expect(await spotify.volumeHistory.contains(0))
        #expect(await spotify.volumeLevel == 60) // set back while paused

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        await waitUntil { await spotify.playCallCount == 1 }
        await waitUntil { await spotify.volumeLevel == 60 }
        #expect(await spotify.commandLog.contains("volume 0"))
        #expect(await spotify.volumeLevel == 60)
    }

    @Test("the fade-in after a resume is not rushed by a cancelled task")
    func fadeInIsNotRushed() async {
        let spotify = MockMusicPlayer()
        await spotify.setVolumeLevel(60)
        let scheduler = ManualDebounceScheduler()
        let rushedSteps = Counter()
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(),
                                      debounceScheduler: scheduler,
                                      fadeSleep: { _ in if Task.isCancelled { await rushedSteps.increment() } })

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        await waitUntil { await spotify.playCallCount == 1 }
        await waitUntil { await spotify.volumeLevel == 60 }
        #expect(await rushedSteps.value == 0)
    }

    @Test("an app that stops during the fade-out leaves the music playing")
    func stopDuringFadeOut() async {
        let spotify = MockMusicPlayer()
        await spotify.setVolumeLevel(60)
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in try? await Task.sleep(for: .milliseconds(5)) })

        let pausing = Task { await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) }
        await waitUntil { await !spotify.volumeHistory.isEmpty } // the fade-out has begun
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await pausing.value

        #expect(await spotify.pauseCallCount == 0)
        #expect(await spotify.volumeLevel == 60)
    }

    @Test("does not resume Spotify that it did not pause")
    func doesNotResumeIfNotPausedByUs() async {
        let spotify = MockMusicPlayer(state: .paused)
        let arbiter = PlaybackArbiter(player: spotify,
            configuration: AppConfiguration(debounceSeconds: 0)
        )

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 0)
    }

    @Test("does not resume while another foreign source is still active")
    func doesNotResumeWithActiveSource() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 0)
    }

    @Test("cancels the pending resume when a new foreign source starts during debounce")
    func cancelsPendingResumeOnNewSource() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: true)
        await scheduler.completeNext()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await spotify.playCallCount == 0)
    }

    @Test("resumes Spotify when Safari stops")
    func resumesWhenSafariStops() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "com.apple.Safari", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.apple.Safari", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    @Test("resumes Spotify when Firefox stops")
    func resumesWhenFirefoxStops() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.mozilla.firefox", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.mozilla.firefox", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    @Test("resumes Spotify when QuickTime Player stops")
    func resumesWhenQuickTimePlayerStops() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    @Test("resumes Spotify when a Chrome renderer helper stops")
    func resumesWhenChromeHelperStops() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "com.google.Chrome.helper", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.google.Chrome.helper", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    // MARK: - PlaybackState reporting

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
        spotify: MockMusicPlayer = MockMusicPlayer(),
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler(),
        stream: StateStream
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: spotify,
            configuration: AppConfiguration(),
            debounceScheduler: scheduler,
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

    @Test("publishes musicPlaying immediately after resume without re-querying Spotify")
    func resumePublishesSpotifyPlayingWithoutRaceCondition() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        // Drain the .pausedByMonitor event.
        _ = await nextState(from: stateStream.stream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        // Simulate Spotify still reporting .paused at this instant (the race the fix closes).
        await spotify.overrideState(.paused)
        await scheduler.completeNext()

        // Must be .musicPlaying — not .musicIdle — even though playerState() returns .paused.
        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicPlaying)
    }

    @Test("publishes pausedByMonitor while a foreign source is active")
    func publishesPausedByMonitorWhileSourceActive() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        let state = await nextState(from: stateStream.stream)
        #expect(state == .pausedByMonitor)
    }

    @Test("refreshPlaybackState publishes musicPlaying when Spotify is playing")
    func refreshPublishesSpotifyPlaying() async {
        let spotify = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, stream: stateStream)

        await arbiter.refreshPlaybackState()

        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicPlaying)
    }

    @Test("refreshPlaybackState publishes musicIdle when Spotify is paused")
    func refreshPublishesSpotifyIdle() async {
        let spotify = MockMusicPlayer(state: .paused)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, stream: stateStream)

        await arbiter.refreshPlaybackState()

        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicIdle)
    }

    // MARK: - Spotify state notifications / user-intent protection

    @Test("user resuming Spotify while a source plays clears pausedByUs and publishes musicPlaying")
    func spotifyPlayingNotificationClearsPausedByUs() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        _ = await nextState(from: stateStream.stream)  // drain .pausedByMonitor

        // User resumes Spotify; Spotify posts PlaybackStateChanged = Playing.
        await spotify.overrideState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        // Spotify plays alongside the other app; we no longer hold it paused.
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)

        // When the source stops, the arbiter must not touch Spotify.
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }
        #expect(await spotify.playCallCount == 0)
    }

    @Test("Spotify quitting clears pausedByUs so nothing is resumed later")
    func spotifyNotRunningClearsPausedByUs() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await spotify.overrideState(.notRunning)
        await arbiter.handlePlayerStateChange(.notRunning)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }
        #expect(await spotify.playCallCount == 0)
    }

    @Test("Spotify stopping clears pausedByUs so nothing is resumed later")
    func spotifyStoppedClearsPausedByUs() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await spotify.overrideState(.stopped)
        await arbiter.handlePlayerStateChange(.stopped)
        _ = await nextState(from: stateStream.stream)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }
        #expect(await spotify.playCallCount == 0)
    }

    @Test("the Paused notification caused by our own pause keeps pausedByUs")
    func ownPauseNotificationKeepsPausedByUs() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    @Test("an unknown Spotify state is ignored and the resume still happens")
    func unknownStateIsIgnored() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handlePlayerStateChange(.unknown)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1)
    }

    @Test("status updates from notifications do not query Spotify through Apple events")
    func notificationsDoNotQuerySpotify() async {
        let spotify = MockMusicPlayer(state: .paused)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handlePlayerStateChange(.paused)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        #expect(await spotify.stateQueryCount == 0)
    }

    // MARK: - Spotify playing on another device

    @Test("does not pause Spotify that plays on another device")
    func doesNotPauseRemotePlayback() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
        #expect(await spotify.stateQueryCount == 0)
    }

    @Test("pauses again once playback is back on this Mac")
    func pausesAfterPlaybackReturns() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.handleLocalPlaybackChange(true)
        await arbiter.handleSourceChange(sourceID: "com.apple.Safari", isPlaying: true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("publishes playingElsewhere while Spotify plays on another device")
    func publishesPlayingElsewhere() async {
        let spotify = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handleLocalPlaybackChange(false)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
    }

    // MARK: - Auto-pause on/off

    @Test("with auto-pause off, a foreign source does not pause Spotify")
    func autoPauseOffDoesNotPause() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(), autoPauseEnabled: false)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
    }

    @Test("turning auto-pause off resumes Spotify that we paused")
    func turningOffResumes() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.setAutoPauseEnabled(false)

        #expect(await spotify.playCallCount == 1)
        #expect(await spotify.state == .playing)
    }

    @Test("turning auto-pause off leaves a Spotify the user paused alone")
    func turningOffRespectsUserPause() async {
        let spotify = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.setAutoPauseEnabled(false)

        #expect(await spotify.playCallCount == 0)
    }

    @Test("turning auto-pause off cancels a pending resume")
    func turningOffCancelsPendingResume() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.setAutoPauseEnabled(false)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        #expect(await spotify.playCallCount == 1) // the immediate resume, not a second one
    }

    @Test("turning auto-pause back on pauses Spotify if an app is already playing")
    func turningOnPausesForActiveSource() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(), autoPauseEnabled: false)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.setAutoPauseEnabled(true)

        #expect(await spotify.pauseCallCount == 1)
    }

    @Test("turning auto-pause back on with nothing playing does nothing")
    func turningOnIdleDoesNothing() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(), autoPauseEnabled: false)

        await arbiter.setAutoPauseEnabled(true)

        #expect(await spotify.pauseCallCount == 0)
    }

    @Test("a new configuration's resume delay applies to the next resume")
    func configurationUpdate() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.setConfiguration(AppConfiguration(timings: TimingSettings(resumeDelay: 1.5)))
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)

        #expect(scheduler.scheduledDelays == [1.5])
    }

    // MARK: - When audio levels are needed (recording indicator)

    private final class NeedsLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Bool] = []
        var values: [Bool] { lock.withLock { _values } }
        func record(_ value: Bool) { lock.withLock { _values.append(value) } }
    }

    @Test("levels are needed only while Spotify plays here or is paused by us, with auto-pause on")
    func audioLevelsNeeded() async {
        let spotify = MockMusicPlayer(state: .paused)
        let scheduler = ManualDebounceScheduler()
        let log = NeedsLog()
        let arbiter = PlaybackArbiter(player: spotify, configuration: AppConfiguration(), debounceScheduler: scheduler,
            onAudioLevelsNeededChange: { log.record($0) }
        )

        await arbiter.refreshPlaybackState()                       // Spotify paused by the user
        await arbiter.handlePlayerStateChange(.playing)           // plays here
        await spotify.overrideState(.playing)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) // we pause it: still needed
        await arbiter.setAutoPauseEnabled(false)                   // resumed and off: not needed
        await arbiter.setAutoPauseEnabled(true)                    // on again; VLC is still active, so Spotify is paused again
        await arbiter.handlePlayerStateChange(.stopped)           // the user takes over

        #expect(log.values == [false, true, false, true, false])
    }

    @Test("levels are not needed while Spotify plays on another device")
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

    @Test("shutdown cancels a pending resume")
    func shutdownCancelsPendingResume() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.shutdown()
        await scheduler.completeNext()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await spotify.playCallCount == 0)
    }

    @Test("a shut-down arbiter ignores new sources")
    func shutdownIgnoresNewSources() async {
        let spotify = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(spotify: spotify)

        await arbiter.shutdown()
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)

        #expect(await spotify.pauseCallCount == 0)
    }

    // MARK: - Resume edge cases

    @Test("resume is skipped when user manually paused Spotify during debounce")
    func resumeSkippedWhenUserPausedSpotifyDuringDebounce() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(spotify: spotify, scheduler: scheduler, stream: stateStream)

        // Source starts → arbiter pauses Spotify.
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        _ = await nextState(from: stateStream.stream)  // drain .pausedByMonitor

        // Source stops → debounce timer starts.
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)

        // During debounce the user also pauses Spotify (still .paused — no state change).
        // Then the user STOPS Spotify entirely.
        await spotify.overrideState(.stopped)

        // Debounce completes — arbiter should NOT call play() because Spotify is .stopped.
        await scheduler.completeNext()
        let state = await nextState(from: stateStream.stream)
        #expect(state == .musicIdle)
        // Confirm play() was never called: Spotify should remain .stopped.
        let finalState = await spotify.playerState()
        #expect(finalState == .stopped)
    }

    @Test("resume is skipped when Spotify is not running at debounce completion")
    func resumeSkippedWhenSpotifyNotRunningAtDebounce() async {
        let spotify = MockMusicPlayer(state: .playing)
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)

        // User quits Spotify before debounce fires.
        await spotify.overrideState(.notRunning)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }

        let playCount = await spotify.playCallCount
        #expect(playCount == 0)
        let finalState = await spotify.playerState()
        #expect(finalState == .notRunning)
    }

    @Test("multiple consecutive source stops each schedule exactly one debounce")
    func multipleStopsScheduleOneDebounceEach() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(spotify: spotify, scheduler: scheduler)

        // Two sources start, then stop one-by-one.
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        // iina still active — no debounce should have fired yet.
        await arbiter.handleSourceChange(sourceID: "com.colliderli.iina", isPlaying: false)
        // Now all sources gone — exactly one debounce should be scheduled.
        #expect(scheduler.scheduledDelays.count == 1)
        await scheduler.completeNext()
        for _ in 0..<20 { await Task.yield() }
        #expect(await spotify.playCallCount == 1)
    }

    // MARK: - Debounce configuration

    @Test("passes the configured debounce delay to the scheduler")
    func appliesConfiguredDebounceDelay() async {
        let spotify = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let config = AppConfiguration(debounceSeconds: 1.5)
        let arbiter = makeArbiter(spotify: spotify, configuration: config, scheduler: scheduler)

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await scheduler.completeNext()
        try? await Task.sleep(for: .milliseconds(50))

        #expect(scheduler.scheduledDelays == [1.5])
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
