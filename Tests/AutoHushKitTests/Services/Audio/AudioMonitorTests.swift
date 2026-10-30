import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("AudioMonitor", .waitsTimeLimit)
struct AudioMonitorTests {
    /// Hysteresis matches production defaults; timers are effectively disabled
    /// so every evaluation is driven explicitly through `provider.triggerChange()`.
    static func config(
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

    static func process(_ objectID: AudioObjectID, _ bundleID: String) -> AudioProcessInfo {
        AudioProcessInfo(objectID: objectID, bundleID: bundleID, pid: pid_t(1000 + objectID))
    }

    /// Stops its monitor once the test is over, however it ends.
    final class Harness {
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
            identifier: any AudioSourceIdentifying? = nil,
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

        /// Starts the monitor and waits until its start-up evaluation has run
        /// (on its queue, with its observing): without the wait, a test could
        /// set processes that the start-up evaluation already sees.
        func start() {
            monitor.start()
            monitor.queue.sync {}
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
