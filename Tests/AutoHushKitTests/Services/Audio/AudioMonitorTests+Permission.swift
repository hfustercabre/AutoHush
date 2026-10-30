import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
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
}
