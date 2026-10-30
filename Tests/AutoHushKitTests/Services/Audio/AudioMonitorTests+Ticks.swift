import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
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
        h.provider.processes = [Self.process(1, "org.example.viewer")] // no HAL change says so
        h.clock.advance(by: 2)
        h.monitor.setDetectionMethod(.openStreams)
        h.provider.flush()
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events == [.init(bundleID: "org.example.viewer", isPlaying: true)])
    }

    @Test("a permission undecided again (reset in System Settings) puts level detection back to waiting for it")
    func permissionUndecidedAgain() {
        let permission = MockAudioCapturePermission(.granted)
        let h = Harness(permission: permission)
        h.start()
        h.step([Self.process(1, "org.example.viewer")], peaks: [1: 0.3])
        #expect(h.modes.value == [.audioLevel])

        permission.current = .notDetermined
        h.step(after: 5.0) // the next re-check
        #expect(h.modes.value == [.audioLevel, .pending])
    }

    @Test("switching the detection method forgets when apps last announced playing: a video-only app's assertion withdrawn meanwhile isn't taken for a pause")
    func methodSwitchForgetsAnnouncements() async {
        let assertions = MockPowerAssertions()
        let name = "com.apple.WebCore: HTMLMediaElement playback"
        var videoOnly = AnnouncedAssertions() // one assertion for video, the display's or the Mac's (Safari)
        videoOnly.learn([PowerAssertion(.system, name), PowerAssertion(.display, name)])
        let h = Harness(configuration: Self.config(startConfirmation: 0, stopGrace: 0), assertions: assertions,
                        learnedAssertions: ["com.example.browser": videoOnly])
        h.monitor.setDetectionMethod(.playbackSignals)
        h.start()
        let browser = [Self.process(1, "com.example.browser")] // pid 1001
        assertions.held = [1001: [PowerAssertion(.display, name)]] // a video shows
        h.step(browser)
        await h.recorder.waitForEvents(count: 1)

        h.monitor.setDetectionMethod(.openStreams)
        h.provider.flush()
        assertions.held = [:] // withdrawn while its output is judged instead
        h.step(after: 1)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.provider.flush()
        h.step(after: 1)
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.map(\.isPlaying) == [true])
    }

    @Test("a release of the taps called off because levels are needed again is cancelled: it can't fire under a later release and end the taps early")
    func calledOffReleaseCancelled() {
        let h = Harness(permission: MockAudioCapturePermission(.granted), releaseDelay: 60)
        h.start()
        h.step([Self.process(1, "org.example.viewer")])
        h.monitor.setAudioLevelsNeeded(false)
        let release = h.monitor.queue.sync { h.monitor.audioLevelsRelease }
        #expect(release != nil)

        h.monitor.setAudioLevelsNeeded(true)
        h.monitor.queue.sync {}
        #expect(release?.isCancelled == true)
    }
}
