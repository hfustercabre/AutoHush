import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
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
}
