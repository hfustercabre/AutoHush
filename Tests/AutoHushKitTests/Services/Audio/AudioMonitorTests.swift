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
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        configuration.minimumStartWithoutVideo = 0 // the tests of AntiDot mode's longer starts set them
        configuration.minimumStartWithOpenStreams = 0
        return configuration
    }

    private static func process(_ objectID: AudioObjectID, _ bundleID: String) -> AudioProcessInfo {
        AudioProcessInfo(objectID: objectID, bundleID: bundleID, pid: pid_t(1000 + objectID))
    }

    /// Stops its monitor once the test is over, however it ends.
    private final class Harness {
        let recorder = ArbiterEventRecorder()
        let provider = MockAudioProcessSnapshotProvider()
        let meter = MockLevelMeter()
        let clock = ManualClock()
        let activeSources = Locked<[[AudioSource]]>([])
        let modes = Locked<[DetectionMode]>([])
        let learned = Locked<[String]>([])
        let monitor: AudioMonitor

        init(
            configuration: AppConfiguration = AudioMonitorTests.config(),
            meter useMeter: Bool = true,
            permission: MockAudioCapturePermission? = nil,
            identifier: (any AudioSourceIdentifying)? = nil,
            ignored: Set<String> = [],
            levelsNeeded: Bool = true,
            releaseDelay: TimeInterval = 0.05,
            assertions: MockPowerAssertions? = nil,
            learnedAssertions: [String: AnnouncedAssertions] = [:]
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
                learnedAssertions: learnedAssertions,
                onAssertionsLearned: { [learned] id, _ in learned.append(id) },
                audioLevelsNeeded: levelsNeeded,
                audioLevelsReleaseDelay: releaseDelay,
                clock: { [clock] in clock.now },
                onActiveSourcesChange: { [activeSources] in activeSources.append($0) },
                onDetectionModeChange: { [modes] in modes.append($0) }
            )
        }

        deinit { monitor.stop() }

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

    // MARK: - Starting and stopping (stream fallback)

    @Test("the tracker's timings, through the monitor: a source starts once it played for the start confirmation, saying when it was first heard")
    func startSaysWhenFirstHeard() async {
        let h = Harness(meter: false)
        h.start()
        h.step(after: 2, [Self.process(1, "org.videolan.vlc")]) // first heard
        let heard = h.clock.now
        h.step(after: 0.5)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        h.step(after: 0.5) // counts as playing
        await h.recorder.waitForEvents(count: 1)
        #expect(h.activeSources.value.last?.map(\.id) == ["org.videolan.vlc"])

        #expect(await h.recorder.events.map(\.isPlaying) == [true])
        #expect(await h.recorder.heardSince == [heard])
    }

    @Test("the tracker's timings, through the monitor: a gap within the stop grace (a new stream for the next track) keeps a source")
    func gapWithinStopGraceKeepsSource() async {
        let h = Harness(meter: false)
        h.start()
        h.step(after: 2, [Self.process(1, "org.videolan.vlc")])
        h.step(after: 1) // counts as playing
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, [])
        h.step(after: 1.5, [Self.process(2, "org.videolan.vlc")]) // the next track's stream
        h.step(after: 0.25, [])
        h.step(after: 1.5)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.count == 1)
    }

    @Test("the tracker's timings, through the monitor: silent for the stop grace, a source stops, saying nothing of when; heard again, it starts anew, from then")
    func silentForStopGraceStops() async {
        let h = Harness(meter: false)
        h.start()
        h.step(after: 2, [Self.process(1, "org.videolan.vlc")]) // first heard
        let heard = h.clock.now
        h.step(after: 1) // counts as playing
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, [])
        h.step(after: 1.5)
        h.step(after: 0.5)
        await h.recorder.waitForEvents(count: 2)
        // Heard again: a new start, from then.
        h.step(after: 1, [Self.process(1, "org.videolan.vlc")])
        let heardAgain = h.clock.now
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 3)

        #expect(await h.recorder.events.map(\.isPlaying) == [true, false, true])
        #expect(await h.recorder.heardSince == [heard, nil, heardAgain])
    }

    // MARK: - Audio level detection

    @Test("a non-zero sample verifies level detection")
    func nonZeroSampleVerifiesLevelDetection() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "org.mozilla.firefox")], peaks: [1: 0.2])
        #expect(h.modes.value == [.audioLevel])
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
    }

    @Test("quiet sound below the threshold does not count as audible")
    func belowThresholdIsSilent() async {
        let h = Harness()
        h.start()
        h.step([Self.process(9, "com.example.verified")], peaks: [9: 0.5]) // verifies
        h.step(after: 0.1, [Self.process(1, "com.example.hiss")], peaks: [1: 0.0001])
        h.step(after: 1.0)
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("until verified, all-zero taps fall back to open streams")
    func unverifiedTapsFallBackToStreams() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
        #expect(h.modes.value.isEmpty)
    }

    @Test("when the permission cannot be read, the player is tapped only until levels are verified")
    func playerTappedOnlyForVerification() async {
        let h = Harness()
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [1, 2])

        h.step(after: 0.25, peaks: [1: 0.4, 2: 0])
        #expect(h.modes.value == [.audioLevel])
        #expect(h.meter.lastMetered == [2])
    }

    /// The music player's process and Safari's, for the tests of Level the volume.
    private static let musicProcess = process(1, TestPlayer.bundleID)
    private static let safariProcess = process(2, "com.apple.Safari")

    /// A started monitor with Level the volume on and the permission granted,
    /// hearing the music alone.
    private static func levelingHarness() -> Harness {
        var configuration = config()
        configuration.levelsMusic = true
        let h = Harness(configuration: configuration, permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([musicProcess], peaks: [1: 0.1])
        return h
    }

    @Test("with Level the volume on, the player is measured too, but only while another app is")
    func levelsMusicMeasuresPlayer() {
        let h = Self.levelingHarness()
        #expect(h.meter.lastMetered == []) // the music alone: no tap
        h.step(after: 0.25, [Self.musicProcess, Self.safariProcess], peaks: [1: 0.1, 2: 0])
        #expect(h.meter.lastMetered == [1, 2])
    }

    @Test("with Level the volume on, the music's loudness before the pause and the apps' during it, calls aside, say how far to lower the volume at the resume")
    func levelsMusic() async throws {
        let h = Self.levelingHarness()
        h.step(after: 0.25, [Self.musicProcess, Self.safariProcess], peaks: [1: 0.1, 2: 0])
        for _ in 0..<4 { h.step(after: 0.25) }
        #expect(await h.monitor.resumeOffsetDB() == nil) // not paused

        h.monitor.setMusicPaused(true)
        h.provider.flush()
        let call = AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003, isRunningInput: true)
        h.step(after: 0.25, [Self.musicProcess, Self.safariProcess, call], peaks: [1: 0, 2: 0.05, 3: 0.5]) // the call's loud voice doesn't count
        for _ in 0..<4 { h.step(after: 0.25) }
        let offset = try #require(await h.monitor.resumeOffsetDB())
        #expect(abs(offset + 6.02) < 0.05) // Safari was 6 dB quieter than the music

        h.monitor.setMusicPaused(false)
        #expect(await h.monitor.resumeOffsetDB() == nil) // resumed: forgotten
    }

    @Test("an app using its microphone is reported in a call, and no longer once its process is gone")
    func callReported() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.safariProcess, AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003, isRunningInput: true)])
        h.step(after: 0.25, [Self.safariProcess])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.log.filter { $0.contains("call") } == ["call us.zoom.xos", "no call us.zoom.xos"])
    }

    @Test("with the permission granted, the player itself is never tapped")
    func playerNotTappedWithPermission() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [2])
    }

    /// An app that keeps its output open while paused.
    private static let radio = process(2, "com.example.radio")

    /// A started monitor with the permission granted, whose radio was
    /// measured silent for 10 s: its tap released.
    private static func releasedRadioHarness() -> Harness {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([radio], peaks: [2: 0])
        h.step(after: 10.1)
        #expect(h.meter.lastMetered == [])
        return h
    }

    @Test("a source silent for 10 s loses its tap and doesn't count as playing")
    func silentSourceReleased() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.radio], peaks: [2: 0])
        #expect(h.meter.lastMetered == [2])
        h.step(after: 5)
        #expect(h.meter.lastMetered == [2])
        h.step(after: 5.1)
        #expect(h.meter.lastMetered == [])
        h.step(after: 3) // no tap, no level: still not counted as playing
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("a source released for its silence is tapped again once its output closes and opens, and released again after 10 s more")
    func releasedSourceTappedWhenOutputReopens() {
        let h = Self.releasedRadioHarness()
        h.step(after: 1, [])
        h.step(after: 1, [Self.radio])
        #expect(h.meter.lastMetered == [2])
        h.step(after: 10.1)
        #expect(h.meter.lastMetered == [])
    }

    @Test("a source released for its silence counts by its open stream once levels aren't measured (AntiDot mode)")
    func releasedSourceCountsWithoutLevels() async {
        let h = Self.releasedRadioHarness()
        h.monitor.setDetectionMethod(.openStreams) // the release is forgotten
        h.provider.flush()
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.radio", isPlaying: true)])
    }

    /// A started monitor with the permission granted, that measured a radio
    /// (pid 1002) and a call saying it plays all along (pid 1003) silent for
    /// 10 s: the radio's tap released, the call's kept.
    private static func silentRadioAndCallHarness(_ assertions: MockPowerAssertions) -> Harness {
        let h = Harness(permission: MockAudioCapturePermission(.granted), assertions: assertions)
        h.start()
        assertions.held = [1003: MockPowerAssertions.playing] // the call says it plays all along
        h.step([radio, process(3, "com.example.call")], peaks: [2: 0, 3: 0])
        h.step(after: 10.1)
        #expect(h.meter.lastMetered == [3])
        return h
    }

    @Test("a source that tells macOS it plays keeps its tap through 10 s of silence (a call's quiet stretch), so its talk is heard")
    func announcingSourceKeepsTap() async {
        let h = Self.silentRadioAndCallHarness(MockPowerAssertions())
        h.step(after: 1)
        #expect(h.meter.lastMetered == [3])
        h.step(after: 0.25, peaks: [2: 0, 3: 0.4]) // the call's talk again
        h.step(after: 1.1)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.call", isPlaying: true)])
    }

    @Test("a source released for its silence is tapped again once it tells macOS it plays")
    func releasedSourceAnnounces() {
        let assertions = MockPowerAssertions()
        let h = Self.silentRadioAndCallHarness(assertions)
        assertions.held = [1002: MockPowerAssertions.playing, 1003: MockPowerAssertions.playing]
        h.step(after: 0.25)
        #expect(h.meter.lastMetered == [2, 3])
    }

    @Test("a source heard within 10 s keeps its tap; its silence counts only while it's measured")
    func audibleSourceKeepsTap() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(2, "com.example.radio")], peaks: [2: 0])
        h.step(after: 8, peaks: [2: 0.3])
        h.step(after: 0.25, peaks: [2: 0])
        h.step(after: 8)
        #expect(h.meter.lastMetered == [2])

        // Not measured for a tick (levels not needed): measured again, its
        // silence starts afresh, so 3 s more don't make it 10.
        h.monitor.setAudioLevelsNeeded(false)
        await h.meter.waitUntilMetered([])
        h.step(after: 0.25)
        h.monitor.setAudioLevelsNeeded(true)
        h.provider.flush()
        #expect(h.meter.lastMetered == [2])
        h.step(after: 3)
        #expect(h.meter.lastMetered == [2])
    }

    // MARK: - Capturing only when needed (recording indicator)

    @Test("nothing is captured while audio levels are not needed")
    func noCaptureWhenNotNeeded() async {
        let h = Harness(
            configuration: Self.config(startConfirmation: 0),
            permission: MockAudioCapturePermission(.granted),
            levelsNeeded: false,
            releaseDelay: 1 // long enough to see the taps still there
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
        #expect(h.modes.value == [.playbackSignals])
    }

    @Test("an unknown app counts as playing while it tells macOS so, and as paused once it stops")
    func powerAssertionDecides() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()

        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player")]) // pid 1001
        await h.recorder.waitForEvents(count: 1)
        #expect(h.learned.value == ["com.example.player"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.player", state: .playing, evidence: .announcing)])

        // Paused: the stream stays open but the assertion is gone.
        assertions.held = [:]
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.example.player", isPlaying: true),
            .init(bundleID: "com.example.player", isPlaying: false),
        ])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.player", state: .silent, evidence: .notAnnouncing)])

        // Playing again.
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 3)
        #expect(h.learned.value == ["com.example.player"]) // learned once
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
        #expect(h.learned.value.isEmpty)
    }

    @Test("apps remembered from earlier launches count as paused without an assertion")
    func rememberedAnnouncingApps() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), assertions: MockPowerAssertions(),
                        learnedAssertions: ["com.example.player": AnnouncedAssertions(system: ["Playing"])])
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.example.player")])
        h.step(after: 1)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("a helper's assertion counts for its app")
    func helperAssertion() async {
        let assertions = MockPowerAssertions()
        assertions.held = [777: MockPowerAssertions.playing] // e.g. the browser's main process; audio comes from a helper
        let identifier = StubSourceIdentifier(
            ["com.google.Chrome.helper": AudioSource(id: "com.google.Chrome", name: "Google Chrome")],
            owners: [777: "com.google.Chrome"]
        )
        let h = Harness(configuration: Self.config(startConfirmation: 0), identifier: identifier, assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)
        #expect(h.learned.value == ["com.google.Chrome"])
    }

    @Test("“Open audio streams only” ignores what apps tell macOS")
    func assertionsIgnoredWithOpenStreams() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, assertions: assertions,
                        learnedAssertions: ["com.example.player": AnnouncedAssertions(system: ["Playing"])])
        h.monitor.setDetectionMethod(.openStreams)
        h.start()
        h.step([Self.process(1, "com.example.player")])
        await h.recorder.waitForEvents(count: 1)
        // Remembered as announcing, no assertion now: still playing by its open stream.
        #expect(await h.recorder.events == [.init(bundleID: "com.example.player", isPlaying: true)])
    }

    @Test("while levels aren't measured, an app known to tell macOS counts as paused once it stops, though its stream stays open (VLC)")
    func assertionsWhileNotMeasuring() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0),
                        permission: MockAudioCapturePermission(.granted), levelsNeeded: false, assertions: assertions)
        h.start()
        assertions.held = [1001: [PowerAssertion(.system, "VLC media playback")]]
        h.step([Self.process(1, "org.videolan.vlc")]) // pid 1001
        await h.recorder.waitForEvents(count: 1)
        #expect(h.meter.lastMetered.isEmpty)
        #expect(h.learned.value == ["org.videolan.vlc"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .playing, evidence: .announcing)])

        // Paused: its stream stays open, without the assertion.
        assertions.held = [:]
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events.last == .init(bundleID: "org.videolan.vlc", isPlaying: false))
        #expect(h.monitor.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .silent, evidence: .notAnnouncing)])
    }

    @Test("measured levels win over what apps tell macOS")
    func levelsWinOverAssertions() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: MockAudioCapturePermission(.granted),
                        assertions: assertions)
        h.start()
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player")], peaks: [1: 0]) // says it plays, but silent
        h.step(after: 1.0, peaks: [1: 0])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.player", state: .silent, evidence: .level(0))])
    }

    @Test("an app using one assertion for video stays playing when its window shows again, and its audio still counts (Safari)")
    func videoOnlyAnnouncer() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        let browser = [Self.process(1, "com.example.browser")] // pid 1001
        let name = "com.apple.WebCore: HTMLMediaElement playback"

        // A visible video, then hidden (the Mac kept awake), then visible again.
        assertions.held = [1001: [PowerAssertion(.display, name)]]
        h.step(browser)
        await h.recorder.waitForEvents(count: 1)
        assertions.held = [1001: [PowerAssertion(.system, name)]]
        h.step(after: 1)
        assertions.held = [1001: [PowerAssertion(.display, name)]]
        h.step(after: 1)
        h.step(after: 1)
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.example.browser", state: .playing, evidence: .announcing)])

        // Paused: counted as stopped while its sound stays on.
        assertions.held = [:]
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 2)

        // Its sound goes off, then audio without video plays: it says nothing, its open output counts.
        h.step(after: 8, [])
        h.step(after: 10, browser)
        await h.recorder.waitForEvents(count: 3)

        // Audio started right after pausing a video keeps its sound on: it counts once the pause
        // can no longer explain the sound.
        assertions.held = [1001: [PowerAssertion(.display, name)]]
        h.step(after: 1)
        assertions.held = [:]
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 4)
        h.step(after: 5)
        h.step(after: 5)
        await h.recorder.waitForEvents(count: 5)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.example.browser", isPlaying: true),
            .init(bundleID: "com.example.browser", isPlaying: false),
            .init(bundleID: "com.example.browser", isPlaying: true),
            .init(bundleID: "com.example.browser", isPlaying: false),
            .init(bundleID: "com.example.browser", isPlaying: true),
        ])
    }

    @Test("in AntiDot mode, sound without video must last 3 s, so a notification sound never pauses the music")
    func longerStartWithoutVideo() async {
        var configuration = Self.config(startConfirmation: 0.5, stopGrace: 2)
        configuration.minimumStartWithoutVideo = 3
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: configuration, assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        let processes = [Self.process(1, "com.example.video"), Self.process(2, "com.example.audio"), Self.process(3, "com.example.chat")]
        let video: Set<PowerAssertion> = [PowerAssertion(.system, "Playing"), PowerAssertion(.display, "Video")]
        // A short sound: the chat app says it plays for 2.5 s.
        assertions.held = [1001: video, 1002: MockPowerAssertions.playing, 1003: MockPowerAssertions.playing]
        let heard = h.clock.now
        h.step(processes)
        h.step(after: 0.5)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.video", isPlaying: true)])

        h.step(after: 2)
        assertions.held[1003] = nil
        h.step(after: 0.25)
        h.step(after: 0.25)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events == [
            .init(bundleID: "com.example.video", isPlaying: true),
            .init(bundleID: "com.example.audio", isPlaying: true),
        ])
        // Each start says when its app was first heard: the audio app's 3 s before it counted.
        #expect(await h.recorder.heardSince == [heard, heard])
        h.step(after: 5)
        #expect(!h.monitor.activeAudioReport().contains { $0.id == "com.example.chat" && $0.state == .playing })
        #expect(await h.recorder.startConfirmations == [3]) // what a pause taken over waits for
    }

    /// A started monitor with the `permission`, a 0.5 s start and AntiDot
    /// mode's longer ones (3 s, 2 s by an open stream), that heard two apps
    /// for half a second.
    private static func startConfirmationHarness(permission: AudioCapturePermission?) -> Harness {
        var configuration = config(startConfirmation: 0.5)
        configuration.minimumStartWithoutVideo = 3
        configuration.minimumStartWithOpenStreams = 2
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: configuration, permission: MockAudioCapturePermission(permission), assertions: assertions)
        h.start()
        // The chat app says it plays (Chromium does for 2.5 s after a short sound); the other says nothing.
        assertions.held = [1002: MockPowerAssertions.playing]
        h.step([process(1, "com.example.audio"), process(2, "com.example.chat")],
               peaks: permission == .granted ? [1: 0.3, 2: 0.3] : [:]) // unreadable: its taps silent so far
        h.step(after: 0.5)
        return h
    }

    @Test("measured levels use the usual start confirmation")
    func usualStartWithLevels() async {
        let h = Self.startConfirmationHarness(permission: .granted)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events.map(\.bundleID) == ["com.example.audio", "com.example.chat"])
        #expect(await h.recorder.startConfirmations == [0.5])
    }

    @Test("with nothing measured (Audio Recording denied, being asked, or unreadable before a first sample), AntiDot mode's longer starts apply",
          arguments: [AudioCapturePermission.denied, .notDetermined, nil])
    func longerStartsWithoutLevels(permission: AudioCapturePermission?) async {
        let h = Self.startConfirmationHarness(permission: permission)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty) // a chat tone pauses nothing

        h.step(after: 1.5) // judged by its open stream: 2 s, as with open streams only
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events.map(\.bundleID) == ["com.example.audio"])
        h.step(after: 1) // telling macOS it plays, without video: 3 s, as in AntiDot mode
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.events.map(\.bundleID) == ["com.example.audio", "com.example.chat"])
        #expect(await h.recorder.startConfirmations == [3])
    }

    @Test("with open streams only, which can't tell video, every app's sound must last 2 s, so an app's chat tone never pauses the music")
    func openStreamsSlowStart() async {
        var configuration = Self.config(startConfirmation: 0.5)
        configuration.minimumStartWithOpenStreams = 2
        let h = Harness(configuration: configuration, meter: false, assertions: MockPowerAssertions())
        h.monitor.setDetectionMethod(.openStreams)
        h.start()
        let app = Self.process(1, "com.example.chat")
        h.step([app])
        h.step(after: 1) // a tone: its stream open about a second
        h.step(after: 0.5, [])
        h.step(after: 2)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)

        h.step(after: 1, [Self.process(2, "com.example.video")])
        h.step(after: 1.5)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        h.step(after: 0.6)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.video", isPlaying: true)])
        #expect(await h.recorder.startConfirmations == [2])
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
        #expect(h.modes.value == [.disabled])

        h.monitor.setDetectionMethod(.audioLevels)
        h.provider.flush()
        #expect(permission.requestCount == 1)
        #expect(h.modes.value == [.disabled, .pending])
    }

    @Test("with the permission unreadable, back to measuring from AntiDot mode, detection is pending, then unavailable once the player's tap stays silent",
          arguments: [DetectionMethod.playbackSignals, .openStreams])
    func backToMeasuringIsPending(from method: DetectionMethod) {
        let h = Harness()
        h.monitor.setPlayerPlaying(true)
        h.monitor.setDetectionMethod(method)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        let away: DetectionMode = method == .playbackSignals ? .playbackSignals : .disabled
        #expect(h.modes.value == [away])

        h.monitor.setDetectionMethod(.audioLevels)
        h.provider.flush()
        #expect(h.modes.value == [away, .pending])
        h.step(after: AudioMonitor.verificationWindow)
        #expect(h.modes.value == [away, .pending, .unavailable])
    }

    @Test("the player playing with a silent tap marks level detection unavailable after the verification window; real samples revise that")
    func silentPlayerTapMeansUnavailable() async {
        let h = Harness()
        h.monitor.setPlayerPlaying(true)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        h.step(after: 14.0)
        #expect(h.modes.value.isEmpty)

        h.step(after: 1.0)
        #expect(h.modes.value == [.unavailable])
        h.step(after: 0.25, peaks: [1: 0.2])
        #expect(h.modes.value == [.unavailable, .audioLevel])
    }

    // MARK: - System Audio Recording permission (TCC)

    @Test("granted permission enables level detection before any sample is heard")
    func grantedPermissionEnablesLevels() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        #expect(h.modes.value == [.audioLevel])
    }

    @Test("with permission granted, a paused player's open stream never counts as playing")
    func pausedPlayerWithOpenStreamIsIgnored() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        // VLC paused: output stream still open, tap delivers silence.
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        h.step(after: 3.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.meter.lastMetered == [1])
    }

    @Test("denied permission falls back to streams without creating taps")
    func deniedPermissionFallsBackWithoutTaps() async {
        let h = Harness(permission: MockAudioCapturePermission(.denied))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)

        #expect(h.modes.value == [.unavailable])
        #expect(h.meter.lastMetered.isEmpty)
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
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
        #expect(h.modes.value.isEmpty)

        permission.complete(granted: true)
        h.provider.flush()
        #expect(h.modes.value == [.audioLevel])
        #expect(h.meter.lastMetered == [1])
    }

    @Test("a permission granted a while after the last HAL change starts the taps at once")
    func grantedPermissionTapsAtOnce() {
        let permission = MockAudioCapturePermission(.notDetermined)
        let h = Harness(permission: permission)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        #expect(h.meter.lastMetered.isEmpty)

        h.clock.advance(by: 2) // the process list is no longer re-read at once
        permission.complete(granted: true)
        h.provider.flush()
        #expect(h.meter.lastMetered == [1])
    }

    @Test("revoking the permission is noticed on the next re-check; once it can't be read, samples decide again")
    func revokedPermissionIsNoticed() async {
        let permission = MockAudioCapturePermission(.granted)
        let h = Harness(permission: permission)
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")], peaks: [1: 0.3])
        #expect(h.meter.lastMetered == [1])

        permission.current = .denied
        h.step(after: 2.0)
        #expect(h.modes.value == [.audioLevel])
        h.step(after: 3.0)
        #expect(h.modes.value == [.audioLevel, .unavailable])
        #expect(h.meter.lastMetered.isEmpty)

        // TCC unreadable at the next re-check: tapped again, its sound proves the levels.
        permission.current = nil
        h.step(after: 5.0)
        #expect(h.meter.lastMetered == [1])
        #expect(h.modes.value == [.audioLevel, .unavailable, .audioLevel])
    }

    @Test("a known permission is not overridden by sample-based inference")
    func knownPermissionIgnoresSampleInference() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.monitor.setPlayerPlaying(true)
        h.start()
        // The player's tap silent for long: inference would say "unavailable".
        h.step([Self.process(1, TestPlayer.bundleID)], peaks: [1: 0])
        h.step(after: 20.0)
        #expect(h.modes.value == [.audioLevel])
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
    }

    // MARK: - The player playing on this Mac vs. another device

    @Test("the player without running output is reported as not playing on this Mac")
    func playerWithoutOutputIsNotLocal() async {
        let h = Harness()
        h.start()
        h.step([])
        await h.recorder.waitForPlayerLocal(count: 1)
        #expect(await h.recorder.playerLocal == [false])
    }

    @Test("the player's output counts as local when levels are unavailable")
    func playerOutputIsLocalWithoutLevels() async {
        let h = Harness(meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForPlayerLocal(count: 2)
        // The start-up evaluation runs before any process exists.
        #expect(await h.recorder.playerLocal == [false, true])
    }

    @Test("the player counts as playing here exactly while its output runs")
    func playerLocalFollowsOutput() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        await h.recorder.waitForPlayerLocal(count: 2)
        h.step(after: 0.25, [])
        await h.recorder.waitForPlayerLocal(count: 3)
        #expect(await h.recorder.playerLocal == [false, true, false])
        #expect(h.meter.lastMetered.isEmpty)
    }

    @Test("a process the player owns is its output, never a source: a web app's WebKit process, or a command-line program it runs",
          arguments: ["com.apple.WebKit.GPU", ""])
    func playerOwnedProcessIsLocal(bundleID: String) async {
        let jukebox = AudioSource(id: TestPlayer.bundleID, name: "Jukebox")
        let identifier = StubSourceIdentifier(["com.apple.WebKit.GPU": jukebox], ownersOfPrograms: [1001: jukebox])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, bundleID)]) // pid 1001
        await h.recorder.waitForPlayerLocal(count: 2)
        #expect(await h.recorder.playerLocal == [false, true])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("the player's local status reaches the arbiter before source events of the same tick")
    func playerLocalStatusPrecedesSourceEvents() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "org.videolan.vlc")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.log == ["playerLocal false", "playerLocal true", "+org.videolan.vlc"])
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
        #expect(h.activeSources.value.last == [AudioSource(id: "com.google.Chrome", name: "Google Chrome")])
        #expect(h.monitor.activeAudioReport() == [.init(id: "com.google.Chrome", name: "Google Chrome", state: .playing)])

        // One helper stops: the app keeps playing.
        h.step(after: 0.25, [Self.process(2, "com.google.Chrome.helper")])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.count == 1)
    }

    @Test("an app whose process is gone keeps its name through its stop grace, and is forgotten once it stops")
    func nameKeptThroughStopGrace() async {
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let identifier = StubSourceIdentifier(["com.google.Chrome.helper": chrome])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.google.Chrome.helper")])
        await h.recorder.waitForEvents(count: 1)

        h.step(after: 0.25, []) // its process is gone: the stop grace runs
        #expect(h.activeSources.value.last == [chrome])
        h.step(after: 2)
        await h.recorder.waitForEvents(count: 2)
        #expect(h.activeSources.value.last == [])
        #expect(h.monitor.queue.sync { h.monitor.knownSources }.isEmpty)
    }

    @Test("a process owned by an excluded app (the player's helper) is never a source")
    func excludedOwnerIsIgnored() async {
        let identifier = StubSourceIdentifier([
            "\(TestPlayer.bundleID).helper": AudioSource(id: TestPlayer.bundleID, name: "Jukebox"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "\(TestPlayer.bundleID).helper")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.isEmpty ?? true)
    }

    @Test("a command-line player (afplay run in Terminal) counts as the app that owns it")
    func commandLinePlayerCountsAsItsOwner() async {
        let terminal = AudioSource(id: "com.apple.Terminal", name: "Terminal")
        let identifier = StubSourceIdentifier([:], ownersOfPrograms: [1001: terminal])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "")])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.apple.Terminal", isPlaying: true)])
        #expect(h.activeSources.value.last == [terminal])
    }

    @Test("a process without a bundle ID that no app owns (a system daemon) never counts")
    func ownerlessProgramIsIgnored() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: StubSourceIdentifier([:]))
        h.start()
        h.step([Self.process(1, "")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.isEmpty ?? true)
        #expect(h.monitor.activeAudioReport().isEmpty)
    }

    @Test("an ignored app is published as playing but never reaches the arbiter")
    func ignoredAppIsPublishedNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.map(\.id) == ["org.videolan.vlc"])
        #expect(h.monitor.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .playing, isIgnored: true)])
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
        // It played all along: not heard just now, so its start says nothing of when.
        #expect(Array(await h.recorder.heardSince.suffix(2)) == [nil, nil])
    }

    @Test("an ignored app that stops playing sends nothing to the arbiter")
    func ignoredAppStoppingIsSilent() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), meter: false, ignored: ["org.videolan.vlc"])
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        h.step(after: 0.25, [])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
        #expect(h.activeSources.value.last?.map(\.id) == [])
    }

    // MARK: - Filtering

    @Test("excluded bundle IDs are never forwarded")
    func excludedBundleIDIsNotForwarded() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.coreaudiod")])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("the monitor's own process is ignored")
    func ownProcessIsIgnored() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.step([AudioProcessInfo(objectID: 1, bundleID: "com.example.self", pid: getpid())])
        h.step(after: 1.0)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
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

    @Test("after a HAL change the process list is re-read at the active rate for a second, then only at the idle rate, so an idle monitor wakes seldom")
    func refreshWindowAfterChange() {
        var configuration = Self.config()
        configuration.activeSampleInterval = 1000 // distinct rates, neither ticking during the test
        let h = Harness(configuration: configuration)
        h.start()
        let interval = { h.monitor.queue.sync { h.monitor.timerInterval } }
        let lastRead = { h.monitor.queue.sync { h.monitor.lastRefresh } }
        let tick = { h.monitor.queue.sync { h.monitor.tick() } }

        h.step() // a HAL change: re-read, then the active rate
        #expect(interval() == 1000)
        h.clock.advance(by: 0.5)
        tick()
        let reread = h.clock.now
        #expect(lastRead() == reread) // within the second: read again
        #expect(interval() == 1000)
        h.clock.advance(by: 0.6)
        tick()
        #expect(lastRead() == reread) // after it: not
        #expect(interval() == configuration.idleSampleInterval)
    }

    @Test("switching the detection method re-reads the process list at once, without a HAL change")
    func detectionMethodSwitchRereads() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false)
        h.start()
        h.provider.processes = [Self.process(1, "org.videolan.vlc")] // no HAL change says so
        h.clock.advance(by: 2)
        h.monitor.setDetectionMethod(.openStreams)
        h.provider.flush()
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events == [.init(bundleID: "org.videolan.vlc", isPlaying: true)])
    }

    // MARK: - Publication and lifecycle

    @Test("active sources are published sorted by name, not by ID")
    func activeSourcesPublishedSorted() async {
        let identifier = StubSourceIdentifier([
            "org.mozilla.firefox": AudioSource(id: "org.mozilla.firefox", name: "Firefox"),
            "com.apple.Safari": AudioSource(id: "com.apple.Safari", name: "Safari"),
        ])
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, identifier: identifier)
        h.start()
        h.step([Self.process(1, "com.apple.Safari"), Self.process(2, "org.mozilla.firefox")])
        await h.recorder.waitForEvents(count: 2)
        #expect(h.activeSources.value.last?.map(\.name) == ["Firefox", "Safari"])
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
    }

    @Test("stop clears sources, stops metering and cancels its timer (a stopped monitor never wakes its queue again), and is idempotent")
    func stopIsIdempotent() throws {
        let h = Harness(configuration: Self.config(startConfirmation: 0))
        h.start()
        h.step([Self.process(1, "org.videolan.vlc")])
        let timer = try #require(h.monitor.queue.sync { h.monitor.timer })
        h.monitor.stop()
        h.monitor.stop()
        h.provider.flush()

        #expect(h.activeSources.value.last?.map(\.id) == [])
        #expect(h.meter.stopAllCount == 1)
        #expect(h.provider.isObserving == false)
        #expect(timer.isCancelled)
    }

    @Test("a stopped monitor keeps no report of the apps it judged, for Diagnostics")
    func stopForgetsReport() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player")])
        await h.recorder.waitForEvents(count: 1)
        #expect(!h.monitor.activeAudioReport().isEmpty)

        h.monitor.stop()
        h.monitor.queue.sync {} // past the stop
        #expect(h.monitor.activeAudioReport().isEmpty)
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
        configuration.minimumStartWithoutVideo = 0 // nothing measured here: AntiDot mode's starts would apply
        configuration.minimumStartWithOpenStreams = 0
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
    /// When each event's app was first heard, as the monitor said, in order.
    private(set) var heardSince: [Date?] = []
    private(set) var playerLocal: [Bool] = []
    /// How long apps take to count, at most, each time the monitor said.
    private(set) var startConfirmations: [TimeInterval] = []
    /// Every call in arrival order, start confirmations aside.
    private(set) var log: [String] = []

    func handleSourceChange(sourceID: String, isPlaying: Bool, heardSince: Date?) async {
        events.append(.init(bundleID: sourceID, isPlaying: isPlaying))
        self.heardSince.append(heardSince)
        log.append("\(isPlaying ? "+" : "-")\(sourceID)")
    }

    func handleLocalPlaybackChange(_ isLocal: Bool) async {
        playerLocal.append(isLocal)
        log.append("playerLocal \(isLocal)")
    }

    func handleStartConfirmationChange(_ longest: TimeInterval) async {
        startConfirmations.append(longest)
    }

    func handleCallChange(sourceID: String, inCall: Bool) async {
        log.append("\(inCall ? "call" : "no call") \(sourceID)")
    }

    func waitForPlayerLocal(count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { playerLocal.count >= count }
    }

    func waitForEvents(count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await TestWait.until(sourceLocation: sourceLocation) { events.count >= count }
    }
}

private struct StubSourceIdentifier: AudioSourceIdentifying {
    let sources: [String: AudioSource]
    let owners: [pid_t: String]
    /// Owners of processes without a bundle ID (command-line programs), by pid.
    let ownersOfPrograms: [pid_t: AudioSource]
    init(_ sources: [String: AudioSource], owners: [pid_t: String] = [:], ownersOfPrograms: [pid_t: AudioSource] = [:]) {
        self.sources = sources
        self.owners = owners
        self.ownersOfPrograms = ownersOfPrograms
    }

    func source(for process: AudioProcessInfo) -> AudioSource {
        if process.bundleID.isEmpty, let owner = ownersOfPrograms[process.pid] { return owner }
        return sources[process.bundleID] ?? AudioSource(id: process.bundleID, name: process.bundleID)
    }

    func sourceID(forPID pid: pid_t) -> String? { owners[pid] }
}
