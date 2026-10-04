import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AudioMonitor")
struct AudioMonitorTests {

    /// Hysteresis matches production defaults; timers are effectively disabled
    /// so every evaluation is driven explicitly through `provider.triggerChange()`.
    private static func config(
        startConfirmation: TimeInterval = 1.0,
        stopGrace: TimeInterval = 2.0
    ) -> AppConfiguration {
        var configuration = AppConfiguration(timings: TimingSettings(startConfirmation: startConfirmation))
        configuration.sourceStopGrace = stopGrace // tests may go below the 1 s users can choose
        configuration.audibleGapTolerance = 0.5
        configuration.activeSampleInterval = 3600
        configuration.idleSampleInterval = 3600
        configuration.musicPlayerBundleIDs = [TestPlayer.bundleID]
        return configuration
    }

    private static func process(_ objectID: AudioObjectID, _ bundleID: String) -> AudioProcessInfo {
        AudioProcessInfo(objectID: objectID, bundleID: bundleID, pid: pid_t(1000 + objectID))
    }

    private struct Harness {
        let recorder = ArbiterEventRecorder()
        let provider = MockAudioProcessSnapshotProvider()
        let meter = MockLevelMeter()
        let clock = ManualClock()
        let activeSources = ValueRecorder<[AudioSource]>()
        let modes = ValueRecorder<DetectionMode>()
        let learned = ValueRecorder<String>()
        let monitor: AudioMonitor

        init(
            configuration: AppConfiguration = AudioMonitorTests.config(),
            meter useMeter: Bool = true,
            permission: MockAudioCapturePermission? = nil,
            identifier: (any AudioSourceIdentifying)? = nil,
            ignored: Set<String> = [],
            levelsNeeded: Bool = true,
            assertions: MockPowerAssertions? = nil,
            announcing: Set<String> = []
        ) {
            monitor = AudioMonitor(
                configuration: configuration,
                arbiter: recorder,
                snapshotProvider: provider,
                levelMeter: useMeter ? meter : nil,
                audioCapturePermission: permission,
                sourceIdentifier: identifier,
                ignoredSourceIDs: ignored,
                powerAssertions: assertions,
                announcingSourceIDs: announcing,
                onAnnouncingSourceLearned: { [learned] in learned.record($0) },
                audioLevelsNeeded: levelsNeeded,
                audioLevelsReleaseDelay: 0.05,
                clock: { [clock] in clock.now },
                onActiveSourcesChange: { [activeSources] in activeSources.record($0) },
                onDetectionModeChange: { [modes] in modes.record($0) }
            )
        }

        /// Starts the monitor and waits until its start-up evaluation has run.
        /// Observing begins before that evaluation, so without the flush a test
        /// could set processes that the start-up evaluation already sees.
        func start() {
            monitor.start()
            provider.waitUntilObserving()
            provider.flush()
        }

        /// Sets the processes, advances the clock and runs one evaluation.
        func step(after seconds: TimeInterval = 0, _ processes: [AudioProcessInfo]? = nil, peaks: [AudioObjectID: Float]? = nil) {
            clock.advance(by: seconds)
            if let processes { provider.processes = processes }
            if let peaks { meter.peaks = peaks }
            provider.triggerChange()
        }
    }

    // MARK: - Hysteresis (stream fallback)

    @Test("a source with an open stream starts only after the start confirmation")
    func startRequiresConfirmation() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.5)
        #expect(await h.recorder.events.isEmpty)

        h.step(after: 0.5)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
        #expect(h.activeSources.values.last?.map(\.id) == ["org.videolan.vlc"])
        h.monitor.stop()
    }

    @Test("a notification-length blip never reaches the arbiter")
    func shortBlipIsIgnored() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, "com.tinyspeck.slackmacgap")])
        h.step(after: 0.6, [])
        h.step(after: 1.0)
        h.step(after: 3.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events.isEmpty)
        h.monitor.stop()
    }

    @Test("a playing source stops only after the stop grace period")
    func stopRequiresGrace() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, "com.apple.QuickTimePlayerX")])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, [])
        h.step(after: 1.5)
        #expect(await h.recorder.events.count == 1)

        h.step(after: 0.5)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.apple.QuickTimePlayerX", isPlaying: true),
            .init(bundleID: "com.apple.QuickTimePlayerX", isPlaying: false),
        ])
        h.monitor.stop()
    }

    @Test("a short gap between tracks does not stop the source")
    func gapBetweenTracksKeepsSourceActive() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, "com.apple.Safari")])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, [])                              // stream closes between videos
        h.step(after: 1.5, [Self.process(2, "com.apple.Safari")]) // next video starts
        h.step(after: 5.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events == [.init(bundleID: "com.apple.Safari", isPlaying: true)])
        h.monitor.stop()
    }

    // MARK: - Audio level detection

    @Test("a non-zero sample verifies level detection")
    func nonZeroSampleVerifiesLevelDetection() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "org.mozilla.firefox")], peaks: [1: 0.2])
        #expect(h.modes.values == [.audioLevel])
        h.monitor.stop()
    }

    @Test("with level detection a silent but open stream stops after the grace period")
    func silentOpenStreamStopsWithLevelDetection() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper")], peaks: [1: 0.3])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)

        // Video paused: the output stream stays open but delivers silence.
        h.step(after: 0.25, peaks: [1: 0])
        h.step(after: 2.0)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events.last == .init(bundleID: "com.google.Chrome.helper", isPlaying: false))
        h.monitor.stop()
    }

    @Test("quiet sound below the threshold does not count as audible")
    func belowThresholdIsSilent() async {
        let h = Harness()
        h.start()
        h.step([Self.process(9, "com.example.verified")], peaks: [9: 0.5]) // verifies
        h.step(after: 0.1, [Self.process(1, "com.example.hiss")], peaks: [1: 0.0001])
        h.step(after: 1.0)
        h.step(after: 1.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events.isEmpty)
        h.monitor.stop()
    }

    @Test("until verified, all-zero taps fall back to open streams")
    func unverifiedTapsFallBackToStreams() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
        #expect(h.modes.values.isEmpty)
        h.monitor.stop()
    }

    @Test("when the permission cannot be read, Spotify is tapped only until levels are verified")
    func spotifyTappedOnlyForVerification() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [1, 2])

        h.step(after: 0.25, peaks: [1: 0.4, 2: 0])
        #expect(h.modes.values == [.audioLevel])
        #expect(h.meter.lastMetered == [2])
        h.monitor.stop()
    }

    @Test("with the permission granted, Spotify itself is never tapped")
    func spotifyNotTappedWithPermission() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [2])
        h.monitor.stop()
    }

    // MARK: - Capturing only when needed (recording indicator)

    @Test("nothing is captured while audio levels are not needed")
    func noCaptureWhenNotNeeded() async {
        let h = Harness(
            configuration: Self.config(startConfirmation: 0),
            permission: MockAudioCapturePermission(.granted),
            levelsNeeded: false
        )
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        await h.recorder.waitForEvents(count: 1)
        #expect(h.meter.lastMetered.isEmpty)
        // Without levels the open stream counts as playing.
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])

        h.monitor.setAudioLevelsNeeded(true)
        h.provider.flush()
        #expect(h.meter.lastMetered == [1])

        h.monitor.setAudioLevelsNeeded(false)
        h.provider.flush()
        #expect(h.meter.lastMetered == [1]) // released only after a short delay
        await h.meter.waitUntilMetered([])
        #expect(h.meter.lastMetered.isEmpty)
        h.monitor.stop()
    }

    @Test("a brief gap in the need for levels keeps the taps")
    func briefGapKeepsTaps() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        #expect(h.meter.lastMetered == [1])

        h.monitor.setAudioLevelsNeeded(false)
        h.monitor.setAudioLevelsNeeded(true)
        try? await Task.sleep(for: .milliseconds(150))
        h.provider.flush()
        #expect(h.meter.lastMetered == [1])
        #expect(h.meter.stopAllCount == 0)
        h.monitor.stop()
    }

    // MARK: - AntiDot mode: playback signals instead of capturing

    @Test("playback signals: nothing is captured or requested, and no app is singled out")
    func playbackSignals() async {
        let permission = MockAudioCapturePermission(.notDetermined)
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: permission,
                        assertions: MockPowerAssertions())
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc"), Self.process(2, "com.example.game")])
        await h.recorder.waitForEvents(count: 2)

        // Neither has told macOS anything yet, so both count by their open stream.
        #expect(await h.recorder.events == [
            .init(bundleID: "com.example.game", isPlaying: true),
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
        ])
        #expect(h.meter.lastMetered.isEmpty)
        #expect(permission.requestCount == 0)
        #expect(h.modes.values == [.playbackSignals])
        h.monitor.stop()
    }

    @Test("an unknown app counts as playing while it tells macOS so, and as paused once it stops")
    func powerAssertionDecides() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()

        assertions.pids = [1001]
        h.step([Self.process(1, "com.example.player")]) // pid 1001
        await h.recorder.waitForEvents(count: 1)
        #expect(h.learned.values == ["com.example.player"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.player", state: .playing, evidence: .announcing)])

        // Paused: the stream stays open but the assertion is gone.
        assertions.pids = []
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.example.player", isPlaying: true),
            .init(bundleID: "com.example.player", isPlaying: false),
        ])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.player", state: .silent, evidence: .notAnnouncing)])

        // Playing again.
        assertions.pids = [1001]
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 3)
        #expect(h.learned.values == ["com.example.player"]) // learned once
        h.monitor.stop()
    }

    @Test("apps that never tell macOS keep the open-stream rule")
    func silentAppsUseOpenStreams() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.example.game")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.game", isPlaying: true)])
        #expect(h.learned.values.isEmpty)
        h.monitor.stop()
    }

    @Test("apps remembered from earlier launches count as paused without an assertion")
    func rememberedAnnouncingApps() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), assertions: MockPowerAssertions(),
                        announcing: ["com.example.player"])
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.example.player")])
        h.step(after: 1)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.recorder.events.isEmpty)
        h.monitor.stop()
    }

    @Test("a helper's assertion counts for its app")
    func helperAssertion() async {
        let assertions = MockPowerAssertions()
        assertions.pids = [777] // e.g. the browser's main process; audio comes from a helper
        let identifier = StubSourceIdentifier(
            ["com.google.Chrome.helper": AudioSource(id: "com.google.Chrome", name: "Google Chrome")],
            owners: [777: "com.google.Chrome"]
        )
        let h = Harness(configuration: Self.config(startConfirmation: 0), identifier: identifier, assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)
        #expect(h.learned.values == ["com.google.Chrome"])
        h.monitor.stop()
    }

    @Test("power assertions are ignored outside AntiDot mode's playback signals", arguments: [DetectionMethod.audioLevels, .openStreams])
    func assertionsOnlyWithPlaybackSignals(method: DetectionMethod) async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, assertions: assertions,
                        announcing: ["com.example.player"])
        h.monitor.setDetectionMethod(method)
        h.start()
        h.step([Self.process(1, "com.example.player")])
        await h.recorder.waitForEvents(count: 1)
        // Remembered as announcing, no assertion now — but only playback signals use that.
        #expect(await h.recorder.events == [.init(bundleID: "com.example.player", isPlaying: true)])
        h.monitor.stop()
    }

    @Test("with measuring turned off, the permission is never requested and nothing is captured")
    func measuringOff() async {
        let permission = MockAudioCapturePermission(.notDetermined)
        let h = Harness(permission: permission)
        h.monitor.setDetectionMethod(.openStreams)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 6)
        #expect(permission.requestCount == 0)
        #expect(h.meter.lastMetered.isEmpty)
        #expect(h.modes.values == [.disabled])

        h.monitor.setDetectionMethod(.audioLevels)
        h.provider.flush()
        #expect(permission.requestCount == 1)
        #expect(h.modes.values == [.disabled, .pending])
        h.monitor.stop()
    }

    @Test("Spotify playing with a silent tap marks level detection unavailable")
    func silentSpotifyTapMeansUnavailable() async {
        let h = Harness()
        h.monitor.setPlayerPlaying(true)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        h.step(after: 14.0)
        #expect(h.modes.values.isEmpty)

        h.step(after: 1.0)
        #expect(h.modes.values == [.unavailable])
        h.monitor.stop()
    }

    @Test("an unavailable verdict is revised once real samples arrive")
    func unavailableRecoversOnSignal() async {
        let h = Harness()
        h.monitor.setPlayerPlaying(true)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        h.step(after: 15.0)
        h.step(after: 0.25, peaks: [1: 0.2])
        #expect(h.modes.values == [.unavailable, .audioLevel])
        h.monitor.stop()
    }

    // MARK: - System Audio Recording permission (TCC)

    @Test("granted permission enables level detection before any sample is heard")
    func grantedPermissionEnablesLevels() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        #expect(h.modes.values == [.audioLevel])
        h.monitor.stop()
    }

    @Test("with permission granted, a paused player's open stream never counts as playing")
    func pausedPlayerWithOpenStreamIsIgnored() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        // VLC paused: output stream still open, tap delivers silence.
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        h.step(after: 3.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events.isEmpty)
        #expect(h.meter.lastMetered == [1])
        h.monitor.stop()
    }

    @Test("denied permission falls back to streams without creating taps")
    func deniedPermissionFallsBackWithoutTaps() async {
        let h = Harness(permission: MockAudioCapturePermission(.denied))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)

        #expect(h.modes.values == [.unavailable])
        #expect(h.meter.lastMetered.isEmpty)
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
        h.monitor.stop()
    }

    @Test("an undecided permission is requested once and taps start when granted")
    func undecidedPermissionIsRequested() async {
        let permission = MockAudioCapturePermission(.notDetermined)
        let h = Harness(permission: permission)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 6.0) // re-check must not request again
        #expect(permission.requestCount == 1)
        #expect(h.meter.lastMetered.isEmpty)
        #expect(h.modes.values.isEmpty)

        permission.complete(granted: true)
        h.provider.flush()
        #expect(h.modes.values == [.audioLevel])
        #expect(h.meter.lastMetered == [1])
        h.monitor.stop()
    }

    @Test("revoking the permission is noticed on the next re-check")
    func revokedPermissionIsNoticed() async {
        let permission = MockAudioCapturePermission(.granted)
        let h = Harness(permission: permission)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0.3])
        #expect(h.meter.lastMetered == [1])

        permission.current = .denied
        h.step(after: 2.0)
        #expect(h.modes.values == [.audioLevel])
        h.step(after: 3.0)
        #expect(h.modes.values == [.audioLevel, .unavailable])
        #expect(h.meter.lastMetered.isEmpty)
        h.monitor.stop()
    }

    @Test("a known permission is not overridden by sample-based inference")
    func knownPermissionIgnoresSampleInference() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.monitor.setPlayerPlaying(true)
        h.start()
        // Spotify's tap silent for long: inference would say "unavailable".
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        h.step(after: 20.0)
        #expect(h.modes.values == [.audioLevel])
        h.monitor.stop()
    }

    @Test("a new silence threshold applies immediately")
    func configurationUpdate() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0.005]) // -46 dBFS: audible at -60
        await h.recorder.waitForEvents(count: 1)

        var quieter = Self.config(startConfirmation: 0, stopGrace: 0)
        quieter.audibleThreshold = 0.01 // -40 dBFS
        h.monitor.setConfiguration(quieter)
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events.last == .init(bundleID: "org.videolan.vlc", isPlaying: false))
        h.monitor.stop()
    }

    // MARK: - Spotify playing on this Mac vs. another device

    @Test("Spotify without running output is reported as not playing on this Mac")
    func spotifyWithoutOutputIsNotLocal() async {
        let h = Harness()
        h.start()
        h.step([])
        await h.recorder.waitForSpotifyLocal(count: 1)
        #expect(await h.recorder.spotifyLocal == [false])
        h.monitor.stop()
    }

    @Test("Spotify output counts as local when levels are unavailable")
    func spotifyOutputIsLocalWithoutLevels() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForSpotifyLocal(count: 2)
        // The start-up evaluation runs before any process exists.
        #expect(await h.recorder.spotifyLocal == [false, true])
        h.monitor.stop()
    }

    @Test("Spotify counts as playing here exactly while its output runs")
    func spotifyLocalFollowsOutput() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForSpotifyLocal(count: 2)
        h.step(after: 0.25, [])
        await h.recorder.waitForSpotifyLocal(count: 3)
        #expect(await h.recorder.spotifyLocal == [false, true, false])
        #expect(h.meter.lastMetered.isEmpty)
        h.monitor.stop()
    }

    @Test("Spotify's local status reaches the arbiter before source events of the same tick")
    func spotifyLocalStatusPrecedesSourceEvents() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "org.videolan.vlc")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.log == ["spotifyLocal false", "spotifyLocal true", "+org.videolan.vlc"])
        h.monitor.stop()
    }

    // MARK: - Owning apps and ignored apps

    @Test("helper processes of one app form a single named source")
    func helpersFormOneSource() async {
        let identifier = StubSourceIdentifier([
            "com.google.Chrome.helper": AudioSource(id: "com.google.Chrome", name: "Google Chrome"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper"), Self.process(2, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.google.Chrome", isPlaying: true)])
        #expect(h.activeSources.values.last == [AudioSource(id: "com.google.Chrome", name: "Google Chrome")])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.google.Chrome", name: "Google Chrome", state: .playing)])

        // One helper stops: the app keeps playing.
        h.step(after: 0.25, [Self.process(2, "com.google.Chrome.helper")])
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.recorder.events.count == 1)
        h.monitor.stop()
    }

    @Test("a process owned by an excluded app (a Spotify helper) is never a source")
    func excludedOwnerIsIgnored() async {
        let identifier = StubSourceIdentifier([
            "com.spotify.client.helper": AudioSource(id: TestPlayer.bundleID, name: "Spotify"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.spotify.client.helper")])
        h.step(after: 1.0)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.values.last?.isEmpty ?? true)
        h.monitor.stop()
    }

    @Test("an ignored app is published as playing but never reaches the arbiter")
    func ignoredAppIsPublishedNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.values.last?.map(\.id) == ["org.videolan.vlc"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .playing, isIgnored: true)])
        h.monitor.stop()
    }

    @Test("ignoring a playing app stops it for the arbiter; un-ignoring starts it again")
    func togglingIgnoreEmitsEvents() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc"), Self.process(2, "com.apple.Safari")])
        await h.recorder.waitForEvents(count: 2)

        h.monitor.setIgnoredSources(["org.videolan.vlc"])
        await h.recorder.waitForEvents(count: 3)
        h.monitor.setIgnoredSources([])
        await h.recorder.waitForEvents(count: 4)

        #expect(Array(await h.recorder.events.suffix(2)) == [
            .init(bundleID: "org.videolan.vlc", isPlaying: false),
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
        ])
        h.monitor.stop()
    }

    @Test("an ignored app that stops playing sends nothing to the arbiter")
    func ignoredAppStoppingIsSilent() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25, [])
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.values.last?.map(\.id) == [])
        h.monitor.stop()
    }

    // MARK: - Filtering

    @Test("excluded bundle IDs are never forwarded")
    func excludedBundleIDIsNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.coreaudiod")])
        h.step(after: 1.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events.isEmpty)
        h.monitor.stop()
    }

    @Test("the monitor's own process is ignored")
    func ownProcessIsIgnored() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([AudioProcessInfo(objectID: 1, bundleID: "com.example.self", pid: getpid())])
        h.step(after: 1.0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await h.recorder.events.isEmpty)
        h.monitor.stop()
    }

    @Test("a bundle stays active while any of its processes is audible")
    func sameBundleMultipleProcesses() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0))
        h.start()
        h.step([Self.process(1, "com.apple.Safari"), Self.process(2, "com.apple.Safari")], peaks: [1: 0.3, 2: 0.3])
        await h.recorder.waitForEvents(count: 1)
        h.step(after: 0.25, peaks: [1: 0, 2: 0.3])
        h.step(after: 0.25, peaks: [1: 0, 2: 0])
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.apple.Safari", isPlaying: true),
            .init(bundleID: "com.apple.Safari", isPlaying: false),
        ])
        h.monitor.stop()
    }

    // MARK: - Tick rate

    @Test("ticks fast only while another app has audio running, a source is tracked, or the list just changed")
    func tickRate() {
        let configuration = AppConfiguration()
        let rate = { (others: Bool, tracking: Bool, changed: Bool) in
            AudioMonitor.tickInterval(otherAppsRunning: others, isTracking: tracking, recentlyChanged: changed,
                                      configuration: configuration)
        }
        // Nothing running, or only the music player: once a second.
        #expect(rate(false, false, false) == configuration.idleSampleInterval)
        #expect(rate(true, false, false) == configuration.activeSampleInterval)
        #expect(rate(false, true, false) == configuration.activeSampleInterval) // e.g. its stop grace
        #expect(rate(false, false, true) == configuration.activeSampleInterval)
        #expect(configuration.activeSampleInterval < configuration.idleSampleInterval)
    }

    // MARK: - Publication and lifecycle

    @Test("active sources are published sorted")
    func activeSourcesPublishedSorted() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, "org.mozilla.firefox"), Self.process(2, "com.apple.Safari")])
        await h.recorder.waitForEvents(count: 2)
        #expect(h.activeSources.values.last?.map(\.id) == ["com.apple.Safari", "org.mozilla.firefox"])
        h.monitor.stop()
    }

    @Test("the active audio report describes each source's state and level")
    func activeAudioReport() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "com.apple.Safari"), Self.process(2, "org.videolan.vlc")], peaks: [1: 0.1, 2: 0])
        #expect(h.monitor.activeAudioReport() == [
            .init(id: "com.apple.Safari", state: .starting, evidence: .level(0.1)),
            .init(id: "org.videolan.vlc", state: .silent, evidence: .level(0)),
        ])
        h.monitor.stop()
    }

    @Test("events are delivered in order")
    func eventsAreOrdered() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false)
        h.start()
        for _ in 0..<20 {
            h.step(after: 0.25, [Self.process(1, "org.videolan.vlc")])
            h.step(after: 0.25, [])
        }
        await h.recorder.waitForEvents(count: 40)
        let events = await h.recorder.events
        #expect(events.count == 40)
        #expect(events.enumerated().allSatisfy { $0.element.isPlaying == $0.offset.isMultiple(of: 2) })
        h.monitor.stop()
    }

    @Test("stop clears sources, stops metering and is idempotent")
    func stopIsIdempotent() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.monitor.stop()
        h.monitor.stop()
        h.provider.flush()

        #expect(h.activeSources.values.last?.map(\.id) == [])
        #expect(h.meter.stopAllCount == 1)
        #expect(h.provider.isObserving == false)
    }

    @Test("a restarted monitor re-emits sources that are still playing")
    func restartReemitsSources() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        await h.recorder.waitForEvents(count: 1)
        h.monitor.stop()
        h.start()
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
        ])
        h.monitor.stop()
    }

    @Test("the timer drives evaluation without HAL callbacks")
    func timerDrivesEvaluation() async {
        let recorder = ArbiterEventRecorder()
        let provider = MockAudioProcessSnapshotProvider()
        provider.processes = [Self.process(1, "org.videolan.vlc")]
        var configuration = AppConfiguration(timings: TimingSettings(startConfirmation: 0.05))
        configuration.sourceStopGrace = 0.05
        configuration.activeSampleInterval = 0.01
        configuration.idleSampleInterval = 0.01
        let monitor = AudioMonitor(
            configuration: configuration,
            arbiter: recorder,
            snapshotProvider: provider,
            levelMeter: nil
        )
        monitor.start()
        await recorder.waitForEvents(count: 1)
        provider.processes = []
        await recorder.waitForEvents(count: 2)
        #expect(await recorder.events == [
            .init(bundleID: "org.videolan.vlc", isPlaying: true),
            .init(bundleID: "org.videolan.vlc", isPlaying: false),
        ])
        monitor.stop()
    }
}

// MARK: - Helpers

/// Records every source event delivered to the arbiter.
private actor ArbiterEventRecorder: PlaybackArbiting {
    struct Event: Equatable, Sendable {
        let bundleID: String
        let isPlaying: Bool
    }

    private(set) var events: [Event] = []
    private(set) var spotifyLocal: [Bool] = []
    /// Every call in arrival order.
    private(set) var log: [String] = []

    func handleSourceChange(sourceID: String, isPlaying: Bool) async {
        events.append(.init(bundleID: sourceID, isPlaying: isPlaying))
        log.append("\(isPlaying ? "+" : "-")\(sourceID)")
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) async {
        spotifyLocal.append(isLocal)
        log.append("spotifyLocal \(isLocal)")
    }

    func waitForSpotifyLocal(count: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while spotifyLocal.count < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func waitForEvents(count: Int) async {
        let deadline = Date().addingTimeInterval(2)
        while events.count < count, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class MockAudioProcessSnapshotProvider: AudioProcessSnapshotProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _processes: [AudioProcessInfo] = []
    private var queue: DispatchQueue?
    private var onChange: (@Sendable () -> Void)?

    var processes: [AudioProcessInfo] {
        get { lock.withLock { _processes } }
        set { lock.withLock { _processes = newValue } }
    }

    var isObserving: Bool { lock.withLock { onChange != nil } }

    func activeProcesses() -> [AudioProcessInfo] { processes }

    func startObserving(on queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
        lock.withLock {
            self.queue = queue
            self.onChange = onChange
        }
    }

    func stopObserving() {
        lock.withLock { onChange = nil }
    }

    func waitUntilObserving() {
        let deadline = Date().addingTimeInterval(2)
        while !isObserving, Date() < deadline { usleep(1000) }
    }

    /// Simulates a HAL change callback and waits until the monitor handled it.
    func triggerChange() {
        let (queue, onChange) = lock.withLock { (self.queue, self.onChange) }
        guard let queue else { return }
        queue.sync { onChange?() }
    }

    /// Waits until all work already queued on the monitor has run.
    func flush() {
        let queue = lock.withLock { self.queue }
        queue?.sync {}
    }
}

private final class MockLevelMeter: AudioLevelMetering, @unchecked Sendable {
    private let lock = NSLock()
    private var _peaks: [AudioObjectID: Float] = [:]
    private var _metered: Set<AudioObjectID> = []
    private var _stopAllCount = 0

    /// Peaks reported for every metered process (missing entries read as 0).
    var peaks: [AudioObjectID: Float] {
        get { lock.withLock { _peaks } }
        set { lock.withLock { _peaks = newValue } }
    }

    var lastMetered: Set<AudioObjectID> { lock.withLock { _metered } }
    var stopAllCount: Int { lock.withLock { _stopAllCount } }

    /// Waits until exactly these processes are metered, e.g. after a delayed release.
    func waitUntilMetered(_ objectIDs: Set<AudioObjectID>) async {
        let deadline = Date().addingTimeInterval(2)
        while lastMetered != objectIDs, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func setMeteredProcesses(_ objectIDs: Set<AudioObjectID>) {
        lock.withLock { _metered = objectIDs }
    }

    func drainPeaks() -> [AudioObjectID: Float] {
        lock.withLock {
            Dictionary(uniqueKeysWithValues: _metered.map { ($0, _peaks[$0] ?? 0) })
        }
    }

    func stopAll() {
        lock.withLock {
            _metered = []
            _stopAllCount += 1
        }
    }
}

private struct StubSourceIdentifier: AudioSourceIdentifying {
    let sources: [String: AudioSource]
    let owners: [pid_t: String]
    init(_ sources: [String: AudioSource], owners: [pid_t: String] = [:]) {
        self.sources = sources
        self.owners = owners
    }

    func source(for process: AudioProcessInfo) -> AudioSource {
        sources[process.bundleID] ?? AudioSource(id: process.bundleID, name: process.bundleID)
    }

    func sourceID(forPID pid: pid_t) -> String? { owners[pid] }
}

private final class MockPowerAssertions: PowerAssertionReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _pids: Set<pid_t> = []
    var pids: Set<pid_t> {
        get { lock.withLock { _pids } }
        set { lock.withLock { _pids = newValue } }
    }
    func pidsKeepingSystemAwake() -> Set<pid_t> { pids }
}

private final class MockAudioCapturePermission: AudioCapturePermissionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: AudioCapturePermission?
    private var _requestCount = 0
    private var pending: (@Sendable (Bool) -> Void)?

    init(_ status: AudioCapturePermission?) { _current = status }

    var current: AudioCapturePermission? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }

    var requestCount: Int { lock.withLock { _requestCount } }

    func status() -> AudioCapturePermission? { current }

    func request(completion: @escaping @Sendable (Bool) -> Void) {
        lock.withLock {
            _requestCount += 1
            pending = completion
        }
    }

    /// Simulates the user answering the system prompt.
    func complete(granted: Bool) {
        let completion = lock.withLock {
            _current = granted ? .granted : .denied
            return pending
        }
        completion?(granted)
    }
}

private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSinceReferenceDate: 0)

    var now: Date { lock.withLock { current } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

private final class ValueRecorder<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Value] = []

    var values: [Value] { lock.withLock { _values } }

    func record(_ value: Value) {
        lock.withLock { _values.append(value) }
    }
}
