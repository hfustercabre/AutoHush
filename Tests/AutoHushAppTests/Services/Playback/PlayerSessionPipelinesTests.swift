import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

/// The monitorings the player session makes: the engine's pipelines, with
/// the session's setup (the pipeline itself is tested with the engine).
@MainActor
@Suite("PlayerSession: its pipelines", .timeLimit(.minutes(1)))
struct PlayerSessionPipelinesTests {
    /// A process ID no process can have, so the real owner lookup finds none.
    private nonisolated static let playerProcess = AudioProcessInfo(objectID: 1, bundleID: TestPlayer.bundleID, pid: 999_998)

    /// The engine's configuration here: an app counts as playing at once, the
    /// music pauses and plays without fading, and the monitor looks only when
    /// the test changes the processes.
    private nonisolated static func configuration() -> AppConfiguration {
        var configuration = AppConfiguration(timings: TimingSettings(startConfirmation: 0, fadesEnabled: false))
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        configuration.activeSampleInterval = 3600 // ticks only when the test changes the processes
        configuration.idleSampleInterval = 3600
        return configuration
    }

    private static func setup(_ settings: MonitoringSettings, learned: [String: AnnouncedAssertions] = [:],
                              resumesHeld: Bool = false) -> PlayerSession.MonitoringSetup {
        PlayerSession.MonitoringSetup(configuration: configuration(), settings: settings,
                                      learnedAssertions: learned, resumesHeld: resumesHeld)
    }

    /// Pipelines sharing `leveler`, reading stand-ins for macOS, with Auto-Pause on.
    private static func pipelines(sharing leveler: CountingLeveler) -> (any SessionMonitoring, any SessionMonitoring) {
        let make = PlayerSession.pipelines(hostedApp: { _ in nil }, volumeLeveler: leveler, readers: {
            MonitoringPipeline.Readers(processes: MockAudioProcessSnapshotProvider(), levelMeter: MockLevelMeter(),
                                       audioCapturePermission: MockAudioCapturePermission(.granted),
                                       powerAssertions: MockPowerAssertions(), outputDisconnects: MockOutputDisconnects())
        })
        let settings = MonitoringSettings(autoPause: true, ignored: [], timings: .defaults, detection: .audioLevels)
        // A pause held for the player chosen before, and the new one's.
        return (make(MockMusicPlayer(), setup(settings), { _ in }), make(MockMusicPlayer(), setup(settings), { _ in }))
    }

    @Test("the session's monitorings are pipelines made with its setup: Auto-Pause, held resumes, ignored apps, detection, learned signals, hosted apps")
    func madeForSession() async {
        // As the app makes them, reading macOS; never started.
        let muting = MockMutingMusicPlayer(MockMusicPlayer())
        let antiDot = MonitoringSettings(autoPause: true, ignored: [], timings: .defaults, detection: .playbackSignals)
        let live = PlayerSession.pipelines(hostedApp: { _ in nil })(muting, Self.setup(antiDot), { _ in })
        #expect(live is MonitoringPipeline)
        #expect(!muting.tapsAreAllowed) // AntiDot mode: no taps
        live.stop()

        // With stand-ins, started: a web app's page plays, loud, telling macOS
        // so; another app, ignored, has its output open.
        let page = AudioProcessInfo(objectID: 2, bundleID: "com.apple.WebKit.WebContent", pid: 999_999)
        let ignored = AudioProcessInfo(objectID: 3, bundleID: "com.example.ignored", pid: 999_997)
        let site = AudioSource(id: "com.example.site", name: "Site")
        let processes = MockAudioProcessSnapshotProvider()
        processes.processes = [Self.playerProcess, page, ignored]
        let meter = MockLevelMeter()
        meter.peaks = [page.objectID: 0.5]
        let assertions = MockPowerAssertions()
        assertions.held = [page.pid: MockPowerAssertions.playing]
        let readers = MonitoringPipeline.Readers(processes: processes, levelMeter: meter,
                                                 audioCapturePermission: MockAudioCapturePermission(.granted),
                                                 powerAssertions: assertions, outputDisconnects: MockOutputDisconnects())
        let player = MockMusicPlayer(state: .playing)
        let updates = PipelineUpdates()
        let levels = MonitoringSettings(autoPause: true, ignored: [ignored.bundleID], timings: .defaults, detection: .audioLevels)
        let monitoring = PlayerSession.pipelines(hostedApp: { $0 == page.pid ? site : nil }, readers: { readers })(
            player, Self.setup(levels, learned: [site.id: AnnouncedAssertions(system: ["Earlier"])], resumesHeld: true),
            { updates.all.append($0) }
        )
        await monitoring.start(takingOverPause: false, asleep: false)
        await TestWait.until { processes.isObserving }
        processes.triggerChange()
        await TestWait.until { updates.playback.last == .pausedByMonitor }
        #expect(await player.pauseCallCount == 1)
        #expect(updates.activeSources.last == [site]) // the page named by its app
        #expect(updates.detection.last == .audioLevel)
        #expect(updates.learned == [site.id: AnnouncedAssertions(system: ["Earlier", "Playing"])])
        #expect(monitoring.activeAudioReport().map(\.isIgnored) == [true, false]) // the ignored app, then the site

        // The site stops counting: its pause stays, resumes being held.
        let told = updates.playback.count
        monitoring.setIgnoredSources([ignored.bundleID, site.id])
        await TestWait.until { await player.playCallCount > 0 || updates.playback.count > told }
        #expect(await player.playCallCount == 0)
        await monitoring.stopAndRestoreVolume()
    }

    @Test("Level the volume turned off reaches the app's one volume leveler once from each of the session's monitorings")
    func levelingOffReachesSharedLeveler() async {
        let leveler = CountingLeveler()
        let (held, current) = Self.pipelines(sharing: leveler)
        var off = Self.configuration()
        off.levelsMusic = false
        held.setConfiguration(off)
        current.setConfiguration(off)
        await TestWait.until { leveler.restores == 2 }
        await held.stopAndRestoreVolume()
        await current.stopAndRestoreVolume()
        #expect(leveler.restores == 2) // one from each, no more
    }
}

/// Counts the volume leveler's put-backs at once, whatever was lowered or
/// not (it lowers nothing).
private final class CountingLeveler: ResumeLeveling {
    private let count = Locked(0)
    var restores: Int { count.value }

    func lower(by decibels: Float) -> UUID? { nil }
    func restore(over duration: TimeInterval, lowered token: UUID) {}
    func restoreNow(lowered token: UUID) { count.increment() }
    func restoreNow() { count.increment() }
}
