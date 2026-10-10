import CoreAudio
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// The pipeline wired as the app wires it, with stand-ins for what it reads
/// from macOS: an app starting to play reaches the arbiter, which pauses the
/// player.
@MainActor
@Suite("MonitoringPipeline", .timeLimit(.minutes(1)))
struct MonitoringPipelineTests {
    /// Process IDs no process can have, so the real owner lookup finds none.
    private nonisolated static let playerProcess = AudioProcessInfo(objectID: 1, bundleID: TestPlayer.bundleID, pid: 999_998)
    private nonisolated static let otherApp = AudioProcessInfo(objectID: 2, bundleID: "org.videolan.vlc", pid: 999_999)

    @MainActor
    private final class Updates {
        var all: [MonitoringPipeline.StatusUpdate] = []
        var activeSources: [[AudioSource]] {
            all.compactMap { if case .activeSources(let sources) = $0 { sources } else { nil } }
        }
    }

    private struct Setup {
        let processes = MockAudioProcessSnapshotProvider()
        let meter = MockLevelMeter()
        let updates = Updates()
        let pipeline: MonitoringPipeline

        @MainActor
        init(player: any MusicPlayer, detectionMethod: DetectionMethod = .audioLevels) {
            var configuration = AppConfiguration(timings: TimingSettings(startConfirmation: 0, fadesEnabled: false))
            configuration.musicPlayerBundleID = TestPlayer.bundleID
            configuration.activeSampleInterval = 3600 // ticks only when the test changes the processes
            configuration.idleSampleInterval = 3600
            processes.processes = [MonitoringPipelineTests.playerProcess, MonitoringPipelineTests.otherApp]
            let updates = updates
            pipeline = MonitoringPipeline(
                player: player,
                configuration: configuration,
                autoPauseEnabled: true,
                ignoredSourceIDs: [],
                detectionMethod: detectionMethod,
                learnedAssertions: [:],
                readers: .init(processes: processes, levelMeter: meter,
                               audioCapturePermission: MockAudioCapturePermission(.granted),
                               powerAssertions: MockPowerAssertions()),
                onStatusUpdate: { updates.all.append($0) }
            )
        }

        /// The other app's sound comes on, loud, as the audio server announces it.
        func otherAppPlays() async {
            meter.peaks = [MonitoringPipelineTests.otherApp.objectID: 0.5]
            await waitUntil { processes.isObserving }
            processes.triggerChange()
        }
    }

    private static func waitUntil(_ condition: () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func waitUntil(_ condition: () async -> Bool) async {
        await Self.waitUntil(condition)
    }

    @Test("once started, another app playing pauses the player, and the menu hears of it")
    func otherAppPausesPlayer() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player)
        await setup.pipeline.start()
        await setup.otherAppPlays()
        await waitUntil { await player.pauseCallCount == 1 }
        #expect(await player.pauseCallCount == 1)
        await waitUntil { setup.updates.activeSources.last?.map(\.id) == ["org.videolan.vlc"] }
        #expect(setup.updates.activeSources.last?.map(\.id) == ["org.videolan.vlc"])
        setup.pipeline.stop()
    }

    @Test("started while the Mac sleeps, nothing is paused")
    func startedAsleep() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player)
        await setup.pipeline.start(asleep: true)
        await setup.otherAppPlays()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await player.pauseCallCount == 0)
        setup.pipeline.stop()
    }

    @Test("a wake while it starts asleep isn't lost: an app playing then pauses the player")
    func wakeWhileStarting() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player)
        let starting = Task { await setup.pipeline.start(asleep: true) }
        await Task.yield() // it has begun
        setup.pipeline.setAsleep(false)
        await starting.value
        await setup.otherAppPlays()
        await waitUntil { await player.pauseCallCount == 1 }
        #expect(await player.pauseCallCount == 1)
        setup.pipeline.stop()
    }

    @Test("stopping stops watching the audio processes and their levels")
    func stopEndsMonitoring() async {
        let setup = Setup(player: MockMusicPlayer(state: .playing))
        await setup.pipeline.start()
        await waitUntil { setup.processes.isObserving }
        await setup.pipeline.stopAndRestoreVolume()
        setup.processes.flush()
        #expect(!setup.processes.isObserving)
        #expect(setup.meter.stopAllCount >= 1)
    }

    @Test("AntiDot mode turns a player's own taps off, with either way of detecting, and measuring turns them back on",
          arguments: [DetectionMethod.playbackSignals, .openStreams])
    func antiDotModeTurnsTapsOff(antiDot: DetectionMethod) async {
        let player = MockMutingMusicPlayer(MockMusicPlayer())
        let setup = Setup(player: player, detectionMethod: antiDot)
        #expect(!player.tapsAreAllowed)
        setup.pipeline.setDetectionMethod(.audioLevels)
        #expect(player.tapsAreAllowed)
        setup.pipeline.setDetectionMethod(antiDot)
        #expect(!player.tapsAreAllowed) // AntiDot mode promises no taps, whichever way it detects
        setup.pipeline.stop()
    }
}
