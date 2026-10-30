import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
    // MARK: - Listening to the player

    @Test("the player is measured alongside another app, never alone: heard within the last half second it's heard, measured half a second with nothing heard it's silent, briefer it's measuring; heard again, the arbiter is told at once; no tap of its own")
    func playerHearingFromLevels() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        let player = Self.process(2, TestPlayer.bundleID)
        h.step([player], peaks: [2: 0.3])
        #expect(h.meter.lastMetered == []) // the music alone: no tap
        #expect(await h.monitor.playerHearing() == .unknown)

        h.step(after: 0.25, [Self.process(1, "org.mozilla.firefox"), player], peaks: [1: 0.2, 2: 0])
        #expect(h.meter.lastMetered == [1, 2])
        h.step(after: 0.25)
        #expect(await h.monitor.playerHearing() == .measuring(remaining: 0.25))
        h.step(after: 0.25)
        #expect(await h.monitor.playerHearing() == .silent) // a muted trailer
        h.step(after: 0.25, peaks: [1: 0.2, 2: 0.3])
        #expect(await h.monitor.playerHearing() == .heard)
        let heard = h.clock.now
        h.step(after: 0.25, peaks: [1: 0.2, 2: 0])
        #expect(await h.monitor.playerHearing() == .heard) // a quiet moment
        h.step(after: 0.25)
        #expect(await h.monitor.playerHearing() == .silent)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.playerHeard == 1)

        // Since a moment (AutoHush's pause): only its sound after it counts.
        let since = heard.addingTimeInterval(0.25)
        #expect(await h.monitor.playerHearing(since: since) == .measuring(remaining: 0.25))
        h.step(after: 0.25, peaks: [1: 0.2, 2: 0.3])
        #expect(await h.monitor.playerHearing(since: since) == .heard)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.playerHeard == 2) // heard again after a silence

        h.step(after: 0.25, [Self.process(1, "org.mozilla.firefox")])
        #expect(await h.monitor.playerHearing() == .silent) // its output closed
        h.monitor.setDetectionMethod(.playbackSignals)
        #expect(await h.monitor.playerHearing() == .unknown) // AntiDot mode measures no levels
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
        h.step([Self.process(1, "org.example.viewer")], peaks: [1: 0])
        h.step(after: 1.0)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "org.example.viewer", isPlaying: true)])
        #expect(h.modes.value.isEmpty)
    }

    @Test("when the permission cannot be read, the player is tapped to verify levels, then only alongside another app")
    func playerTappedOnlyForVerification() async {
        let alone = Harness()
        alone.start()
        alone.step([Self.process(1, TestPlayer.bundleID)])
        #expect(alone.meter.lastMetered == [1])
        alone.step(after: 0.25, peaks: [1: 0.4])
        #expect(alone.meter.lastMetered == []) // verified: not tapped alone

        let h = Harness()
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [1, 2])

        h.step(after: 0.25, peaks: [1: 0.4, 2: 0])
        #expect(h.modes.value == [.audioLevel])
        #expect(h.meter.lastMetered == [1, 2]) // now alongside Safari, for whether it's heard
        h.step(after: 0.25, [Self.process(1, TestPlayer.bundleID)])
        #expect(h.meter.lastMetered == []) // never alone
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

    @Test("with Level the volume on too, the player is measured only while another app is")
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

    // MARK: - Capturing only when needed (recording indicator)

    @Test("nothing is captured while audio levels are not needed")
    func noCaptureWhenNotNeeded() async {
        let h = Harness(
            configuration: Self.config(startConfirmation: 0),
            permission: MockAudioCapturePermission(.granted),
            levelsNeeded: false,
            releaseDelay: 60 // the taps still there meanwhile; the release is run by hand
        )
        h.start()
        h.step([Self.process(1, "org.example.viewer")], peaks: [1: 0])
        await h.recorder.waitForEvents(count: 1)
        #expect(h.meter.lastMetered.isEmpty)
        // Without levels the open stream counts as playing.
        #expect(await h.recorder.events == [.init(bundleID: "org.example.viewer", isPlaying: true)])

        h.monitor.setAudioLevelsNeeded(true)
        h.provider.flush()
        #expect(h.meter.lastMetered == [1])

        h.monitor.setAudioLevelsNeeded(false)
        h.provider.flush()
        #expect(h.meter.lastMetered == [1]) // released only after a short delay
        // The delay's end, without waiting for it: its release run now.
        h.monitor.queue.sync { h.monitor.audioLevelsRelease?.perform() }
        #expect(h.meter.lastMetered.isEmpty)
    }

    @Test("a brief gap in the need for levels keeps the taps")
    func briefGapKeepsTaps() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, "org.example.viewer")])
        #expect(h.meter.lastMetered == [1])

        h.monitor.setAudioLevelsNeeded(false)
        let release = h.monitor.queue.sync { h.monitor.audioLevelsRelease }
        #expect(release != nil)
        h.monitor.setAudioLevelsNeeded(true)
        // The delay's end, without waiting for it: called off, it releases nothing.
        h.monitor.queue.sync { release?.perform() }
        #expect(h.meter.lastMetered == [1])
    }
}
