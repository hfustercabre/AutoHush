import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension AudioMonitorTests {
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

    /// The player, playing (`setPlayerPlaying`).
    private static let player = process(1, TestPlayer.bundleID)

    /// A started monitor with the permission granted and the player
    /// playing, whose radio was measured silent for 10 s beside it: its
    /// tap released, and the player's with it.
    private static func releasedRadioWithPlayerHarness() -> Harness {
        let h = Harness(permission: MockAudioCapturePermission(.granted))
        h.monitor.setPlayerPlaying(true)
        h.start()
        h.step([player, radio], peaks: [2: 0])
        #expect(h.meter.lastMetered == [1, 2])
        h.step(after: 10.1)
        #expect(h.meter.lastMetered == [])
        return h
    }

    @Test("while the player plays, a source released for its silence is listened to for half a second every 30 s, without the player; still silent, it stays released")
    func quietSourceListenedToAgain() async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.step(after: 29.5)
        #expect(h.meter.lastMetered == [])
        h.step(after: 0.75) // 30 s since its release
        #expect(h.meter.lastMetered == [2])
        h.step(after: 0.25)
        #expect(h.meter.lastMetered == [2])
        h.step(after: 0.3) // the half second is over
        #expect(h.meter.lastMetered == [])
        h.step(after: 29.5) // 30 s from that listen, not from the release
        #expect(h.meter.lastMetered == [])
        h.step(after: 0.75)
        #expect(h.meter.lastMetered == [2])
        await h.monitor.eventsDelivered()
        #expect(await h.recorder.events.isEmpty)
    }

    @Test("a source heard as it's listened to again is tapped again, the player beside it, and counts as playing")
    func quietSourceHeardAgain() async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.step(after: 30.25)
        #expect(h.meter.lastMetered == [2])
        h.step(after: 0.25, peaks: [2: 0.4]) // a game's sound again
        #expect(h.meter.lastMetered == [1, 2])
        h.step(after: 0.5)
        h.step(after: 0.6) // past the listen, still measured
        #expect(h.meter.lastMetered == [1, 2])
        await h.recorder.waitForEvents(count: 1)
        #expect(await h.recorder.events == [.init(bundleID: "com.example.radio", isPlaying: true)])
    }

    @Test("no listen while the player doesn't play, nor in AntiDot mode; one under way ends once the player stops")
    func quietSourceListenedToOnlyWhilePlayerPlays() {
        let h = Self.releasedRadioWithPlayerHarness()
        h.monitor.setPlayerPlaying(false)
        h.step(after: 40)
        #expect(h.meter.lastMetered == [])

        h.monitor.setPlayerPlaying(true) // over 30 s since its release: listened to at once
        h.step(after: 0.25)
        #expect(h.meter.lastMetered == [2])
        h.monitor.setPlayerPlaying(false)
        h.step(after: 0.25)
        #expect(h.meter.lastMetered == [])

        h.monitor.setPlayerPlaying(true)
        h.monitor.setDetectionMethod(.playbackSignals)
        h.provider.flush()
        h.step(after: 40)
        #expect(h.meter.lastMetered == [])
    }

    @Test("an ignored app released for its silence isn't listened to again (R1): no recording dot for an app that can't pause the music")
    func ignoredQuietSourceNotListenedTo() async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.monitor.setIgnoredSources(["com.example.radio"])
        h.step(after: 40)
        #expect(h.meter.lastMetered == [])
        #expect(await h.monitor.listenToQuietApps() == false) // nothing to listen to, at once
    }

    @Test("levels no longer needed (Auto-Pause off), the apps released for their silence aren't listened to again, nor on request: no recording dot for nothing")
    func quietSourceNotListenedToWithoutLevels() async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.monitor.setAudioLevelsNeeded(false)
        h.monitor.queue.sync { h.monitor.audioLevelsRelease?.perform() } // the release's delay over
        h.step(after: 40)
        #expect(h.meter.lastMetered == [])
        #expect(await h.monitor.listenToQuietApps() == false) // no listen, at once
    }

    @Test("asked before a resume, the apps released for their silence are listened to once, the player paused (R2): still silent, they stay released", arguments: [false, true])
    func quietSourcesListenedToOnRequest(heard: Bool) async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.monitor.setPlayerPlaying(false) // paused by AutoHush: no listen every 30 s
        h.step(after: 5)
        let monitor = h.monitor
        let asked = Task { await monitor.listenToQuietApps() }
        await h.meter.waitUntilMetered([2])
        h.step(after: 0.25, peaks: heard ? [2: 0.4] : [2: 0])
        h.step(after: 0.3, peaks: heard ? [2: 0.4] : [:]) // the half second is over
        #expect(await asked.value == heard)
        // Heard, it's tapped as any app (the player too); else released again.
        #expect(h.meter.lastMetered == (heard ? [1, 2] : []))
    }

    @Test("asked before a resume, an ignored app released for its silence that says it plays meanwhile isn't heard: it can't pause the music")
    func ignoredQuietSourceAnnouncingDuringAskedListen() async {
        let assertions = MockPowerAssertions()
        let h = Harness(permission: MockAudioCapturePermission(.granted), ignored: ["com.example.game"], assertions: assertions)
        h.monitor.setPlayerPlaying(true)
        h.start()
        h.step([Self.player, Self.radio, Self.process(3, "com.example.game")], peaks: [2: 0, 3: 0])
        h.step(after: 10.1) // both released for their silence
        #expect(h.meter.lastMetered == [])
        h.monitor.setPlayerPlaying(false) // paused by AutoHush
        h.step(after: 5)
        let monitor = h.monitor
        let asked = Task { await monitor.listenToQuietApps() }
        await h.meter.waitUntilMetered([2]) // the radio only
        assertions.held = [1003: MockPowerAssertions.playing] // the ignored game says it plays
        h.step(after: 0.25, peaks: [2: 0])
        h.step(after: 0.3) // the half second is over
        #expect(await asked.value == false)
    }

    @Test("an app ignored while it's listened to again is let go at once")
    func quietSourceIgnoredDuringListen() {
        let h = Self.releasedRadioWithPlayerHarness()
        h.step(after: 30.25)
        #expect(h.meter.lastMetered == [2])
        h.monitor.setIgnoredSources(["com.example.radio"])
        h.monitor.queue.sync {} // no tick: still within the half second
        #expect(h.meter.lastMetered == [])
    }

    @Test("a listen asked for ends unheard if the monitor stops during it, so the resume waiting on it goes on")
    func askedListenEndsAtStop() async {
        let h = Self.releasedRadioWithPlayerHarness()
        h.monitor.setPlayerPlaying(false)
        let monitor = h.monitor
        let asked = Task { await monitor.listenToQuietApps() }
        await h.meter.waitUntilMetered([2])
        h.monitor.stop()
        #expect(await asked.value == false)
    }
}
