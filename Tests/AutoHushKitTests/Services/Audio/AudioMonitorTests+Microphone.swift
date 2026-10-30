import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
    // MARK: - Pause for the microphone (Settings → Advanced)

    /// Zoom with only its microphone on: no sound output (a call starting silent).
    private static let microphoneOnly = AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003,
                                                         isRunningInput: true, isRunningOutput: false)

    /// The tests' configuration with Pause for the microphone on.
    private static func microphoneConfig(startConfirmation: TimeInterval = 0.5) -> AppConfiguration {
        var configuration = config(startConfirmation: startConfirmation)
        configuration.pausesForMicrophone = true
        return configuration
    }

    @Test("with Pause for the microphone on, an app with only its microphone on is in a call at once, counts as playing after a second, and stops once it's been off for the stop grace")
    func microphoneOnlyPauses() async {
        let h = Harness(configuration: Self.microphoneConfig(), permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.microphoneOnly])
        h.step(after: 0.5)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.log.filter { $0.contains("zoom") } == ["call us.zoom.xos"])
        h.step(after: 0.5)
        await h.recorder.waitForEvents(count: 1)
        h.step(after: 0.25, [])
        h.step(after: 2)
        await h.recorder.waitForEvents(count: 2)
        #expect(await h.recorder.log.filter { $0.contains("zoom") } == ["call us.zoom.xos", "+us.zoom.xos", "no call us.zoom.xos", "-us.zoom.xos"])
    }

    @Test("an app that counts only for its microphone is published so, until it makes a sound")
    func microphoneOnlyPublished() async {
        let h = Harness(configuration: Self.microphoneConfig(), permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.microphoneOnly])
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 1)
        #expect(h.activeSources.value.last?.map(\.isMicrophoneOnly) == [true])
        let speaking = AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003, isRunningInput: true)
        h.step(after: 0.25, [speaking], peaks: [3: 0.5]) // the other side speaks
        h.step(after: 0.25, peaks: [3: 0]) // and is silent again: still a sound made
        #expect(h.activeSources.value.last?.map(\.isMicrophoneOnly) == [false])
    }

    @Test("with Pause for the microphone on, an app playing with its microphone on counts after a second, even when its sound must play longer")
    func microphoneShortensStart() async {
        let h = Harness(configuration: Self.microphoneConfig(startConfirmation: 3), permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([AudioProcessInfo(objectID: 3, bundleID: "us.zoom.xos", pid: 1003, isRunningInput: true)], peaks: [3: 0.5])
        h.step(after: 1)
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events.map(\.bundleID) == ["us.zoom.xos"])
        #expect(await h.recorder.startConfirmations.last == 3) // what the sound alone needs, the longest
    }

    @Test("with Pause for the microphone off, an app with only its microphone on isn't read: no pause, no call")
    func microphoneOnlyUnreadWhenOff() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.microphoneOnly])
        h.step(after: 2)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.log.filter { $0.contains("zoom") }.isEmpty)
    }

    @Test("turning Pause for the microphone on reads the apps with only their microphone on at the next tick, without waiting for the process list to change")
    func microphoneSwitchRereads() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.microphoneOnly]) // off: not read
        h.clock.advance(by: 2) // past the change's window: the list isn't re-read at each tick
        h.monitor.setConfiguration(Self.microphoneConfig())
        h.monitor.queue.sync { h.monitor.tick() }
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.log.filter { $0.contains("zoom") } == ["call us.zoom.xos"])
    }

    @Test("an ignored app's microphone pauses nothing and makes no call")
    func ignoredMicrophone() async {
        let h = Harness(configuration: Self.microphoneConfig(), permission: MockAudioCapturePermission(.granted), ignored: ["us.zoom.xos"])
        h.start()
        h.step([Self.microphoneOnly])
        h.step(after: 2)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.log.filter { $0.contains("zoom") }.isEmpty)
    }

    @Test("with the permission granted, the player is never tapped alone, only alongside another app")
    func playerNotTappedWithPermission() async {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.start()
        h.step([Self.process(1, TestPlayer.bundleID)])
        #expect(h.meter.lastMetered == [])
        h.step([Self.process(1, TestPlayer.bundleID), Self.process(2, "com.apple.Safari")])
        #expect(h.meter.lastMetered == [1, 2])
    }

    /// An app that keeps its output open while paused.
}
