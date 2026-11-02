import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
    // MARK: - Apps that count only by their open sound (Playing Now's "Sound on, may be paused")

    /// What the last published active apps say: each one's ID and whether it
    /// counts only by its open sound.
    private static func openOutput(_ h: Harness) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: (h.activeSources.value.last ?? []).map { ($0.id, $0.isOpenOutputOnly) })
    }

    @Test("in AntiDot mode's “What apps tell macOS”, an app that never told macOS it plays counts only by its open sound; one that tells, not")
    func openOutputWithPlaybackSignals() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player"), Self.process(2, "com.example.game")]) // pids 1001, 1002
        await h.recorder.waitForEvents(count: 2)
        #expect(Self.openOutput(h) == ["com.example.player": false, "com.example.game": true])
        #expect(await h.monitor.appsNotMeasuredYet().isEmpty) // never measured here: known by what it has
    }

    @Test("with “Open audio streams only”, where every app counts by its open sound as the user chose, none is singled out")
    func noOpenOutputWithOpenStreams() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), meter: false, assertions: MockPowerAssertions())
        h.monitor.setDetectionMethod(.openStreams)
        h.start()
        h.step([Self.process(1, "com.example.game")])
        await h.recorder.waitForEvents(count: 1)
        #expect(Self.openOutput(h) == ["com.example.game": false])
    }

    @Test("without Audio Recording outside AntiDot mode, an app judged by its open sound is singled out; one telling macOS it plays, not")
    func openOutputWithoutAudioRecording() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: MockAudioCapturePermission(.denied),
                        assertions: assertions)
        h.start()
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player"), Self.process(2, "com.example.game")])
        await h.recorder.waitForEvents(count: 2)
        #expect(h.modes.value == [.unavailable])
        #expect(Self.openOutput(h) == ["com.example.player": false, "com.example.game": true])
        #expect(await h.monitor.appsNotMeasuredYet().isEmpty) // never measured here: known by what it has
    }

    @Test("with audio levels measured, no app is singled out, measured or not")
    func noOpenOutputWithLevels() async {
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: MockAudioCapturePermission(.granted),
                        levelsNeeded: false, assertions: MockPowerAssertions())
        h.start()
        h.step([Self.process(1, "com.example.game")]) // no tap while levels aren't needed: judged by its open stream
        await h.recorder.waitForEvents(count: 1)
        #expect(h.modes.value == [.audioLevel])
        #expect(Self.openOutput(h) == ["com.example.game": false])
    }

    @Test("where levels can be measured, an app counted by its open output while they weren't needed isn't measured yet until it's heard; one telling macOS it plays is known")
    func appsNotMeasuredYetUntilHeard() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0), permission: MockAudioCapturePermission(.granted),
                        levelsNeeded: false, assertions: assertions)
        h.start()
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step([Self.process(1, "com.example.player"), Self.process(2, "com.example.game")]) // no taps: judged without levels
        await h.recorder.waitForEvents(count: 2)
        #expect(h.modes.value == [.audioLevel])
        #expect(await h.monitor.appsNotMeasuredYet() == ["com.example.game"])

        h.monitor.setAudioLevelsNeeded(true) // the music plays
        h.provider.flush()
        h.step(after: 0.25, peaks: [1: 0, 2: 0]) // measured silent: still not known to play, until its stop grace ends
        #expect(await h.monitor.appsNotMeasuredYet() == ["com.example.game"])
        h.step(after: 0.25, peaks: [1: 0, 2: 0.5]) // heard
        #expect(await h.monitor.appsNotMeasuredYet().isEmpty)
    }

    @Test("an app that counts only for its microphone keeps saying so, not that its sound is open")
    func microphoneWinsOverOpenOutput() async {
        var configuration = Self.config(startConfirmation: 0)
        configuration.pausesForMicrophone = true
        let h = Harness(configuration: configuration, assertions: MockPowerAssertions())
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003, isRunningInput: true, isRunningOutput: false)])
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 1)
        #expect(h.activeSources.value.last?.map(\.isMicrophoneOnly) == [true])
        #expect(Self.openOutput(h) == ["us.zoom.xos": false])
    }

    @Test("an app keeps what was last known while it stays active after its sound closes (the stop grace), and loses it once it tells macOS it plays")
    func openOutputLastKnown() async {
        let assertions = MockPowerAssertions()
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 2), assertions: assertions)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        h.step([Self.process(1, "com.example.game")])
        await h.recorder.waitForEvents(count: 1)
        #expect(Self.openOutput(h) == ["com.example.game": true])

        // Its output closes: still active through the stop grace, as it was.
        h.step(after: 0.25, [])
        #expect(Self.openOutput(h) == ["com.example.game": true])

        // Open again, and now it tells macOS it plays.
        assertions.held = [1001: MockPowerAssertions.playing]
        h.step(after: 0.25, [Self.process(1, "com.example.game")])
        #expect(Self.openOutput(h) == ["com.example.game": false])
    }
}
