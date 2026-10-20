import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
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

    /// The engine's configuration here: an app counts as playing at once, the
    /// music pauses and plays without fading, and the monitor looks only when
    /// the test changes the processes.
    private nonisolated static func configuration(stopGrace: TimeInterval = TimingSettings.defaults.stopGrace) -> AppConfiguration {
        var configuration = AppConfiguration(timings: TimingSettings(startConfirmation: 0, fadesEnabled: false))
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        configuration.sourceStopGrace = stopGrace
        configuration.activeSampleInterval = 3600 // ticks only when the test changes the processes
        configuration.idleSampleInterval = 3600
        return configuration
    }

    private struct Setup {
        let processes = MockAudioProcessSnapshotProvider()
        let meter = MockLevelMeter()
        let updates = PipelineUpdates()
        let configuration: AppConfiguration
        let pipeline: MonitoringPipeline

        /// `stopGrace`: how long a playing app must be quiet to count as stopped.
        @MainActor
        init(player: any MusicPlayer, detectionMethod: DetectionMethod = .audioLevels,
             stopGrace: TimeInterval = TimingSettings.defaults.stopGrace) {
            let configuration = MonitoringPipelineTests.configuration(stopGrace: stopGrace)
            self.configuration = configuration
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
            await TestWait.until { processes.isObserving }
            processes.triggerChange()
        }
    }

    @Test("once started, another app playing pauses the player, and the menu and Diagnostics hear of it; ignored, the music comes back")
    func otherAppPausesPlayer() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player)
        await setup.pipeline.start()
        await setup.otherAppPlays()
        await TestWait.until { await player.pauseCallCount == 1 }
        await TestWait.until { setup.updates.activeSources.last?.map(\.id) == ["org.videolan.vlc"] }
        #expect(setup.pipeline.activeAudioReport() == [.init(id: "org.videolan.vlc", state: .playing, evidence: .level(0.5))])

        setup.pipeline.setIgnoredSources(["org.videolan.vlc"])
        await TestWait.until { await player.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        #expect(await player.playCallCount == 1)
        setup.pipeline.stop()
    }

    @Test("each command reaches the arbiter: held resumes, Auto-Pause, new timings, the user's own play and pause, an app no longer ignored")
    func commandsReachArbiter() async {
        // The user plays and pauses it: its observer reports the changes.
        let mock = MockMusicPlayer(state: .playing)
        // A minute: Auto-Pause back on pauses only after it, unless shorter timings reached the arbiter.
        let setup = Setup(player: mock, stopGrace: 60)
        await setup.pipeline.start()
        await setup.otherAppPlays()
        await TestWait.until { setup.updates.playback.last == .pausedByMonitor }
        #expect(await mock.pauseCallCount == 1)

        // Held, nothing resumes, not even with Auto-Pause off (the arbiter's state, told three
        // times: held, off, and the resume held).
        var told = setup.updates.playback.count
        setup.pipeline.holdResumes(true)
        setup.pipeline.setAutoPauseEnabled(false)
        await TestWait.until { await mock.playCallCount > 0 || setup.updates.playback.count >= told + 3 }
        #expect(await mock.playCallCount == 0)
        setup.pipeline.holdResumes(false)
        await TestWait.until { await mock.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        #expect(await mock.playCallCount == 1)

        // Shorter timings, then Auto-Pause back on: paused again for the app still playing.
        var shorter = setup.configuration
        shorter.sourceStopGrace = 0
        setup.pipeline.setConfiguration(shorter)
        setup.pipeline.setAutoPauseEnabled(true)
        await TestWait.until { setup.updates.playback.last == .pausedByMonitor }
        #expect(await mock.pauseCallCount == 2)

        // The user plays it during that pause, then pauses it: it's theirs, so it stays paused once the app stops.
        await mock.userSets(.playing)
        await TestWait.until { setup.updates.playback.last == .musicPlaying }
        await mock.userSets(.paused)
        await TestWait.until { setup.updates.playback.last == .musicIdle }
        told = setup.updates.playback.count
        setup.pipeline.setIgnoredSources([Self.otherApp.bundleID])
        await TestWait.until { await mock.playCallCount > 1 || setup.updates.playback.count > told }
        #expect(await mock.playCallCount == 1)

        // Played again, it can't be paused once the app counts again: the menu hears why.
        await mock.setFailPause(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await mock.userSets(.playing)
        await TestWait.until { setup.updates.playback.last == .musicPlaying }
        setup.pipeline.setIgnoredSources([])
        await TestWait.until { !setup.updates.pauseFailures.isEmpty }
        #expect(setup.updates.pauseFailures == [.playerCommandFailed(.pressIgnored)])
        setup.pipeline.stop()
    }

    @Test("started while the Mac sleeps, nothing is paused")
    func startedAsleep() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player)
        await setup.pipeline.start(asleep: true)
        await setup.otherAppPlays()
        await setup.pipeline.eventsDelivered()
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
        _ = await starting.value
        await setup.otherAppPlays()
        await TestWait.until { await player.pauseCallCount == 1 }
        setup.pipeline.stop()
    }

    @Test("stopping stops watching the audio processes and their levels; stopped while it starts, it never watches them")
    func stopEndsMonitoring() async {
        let setup = Setup(player: MockMusicPlayer(state: .playing))
        await setup.pipeline.start()
        await TestWait.until { setup.processes.isObserving }
        await setup.pipeline.stopAndRestoreVolume()
        setup.processes.flush()
        #expect(!setup.processes.isObserving)
        #expect(setup.meter.stopAllCount >= 1)

        // Stopped while it asks the player's state, as it starts; then while
        // it asks again, to take a pause over.
        for takingOver in [false, true] {
            let player = MockMusicPlayer(state: .paused)
            let answers = ManualSleep()
            await player.setBeforeStateAnswer { await answers.sleep(.zero) }
            let stopped = Setup(player: player)
            let starting = Task { await stopped.pipeline.start(takingOverPause: takingOver) }
            await TestWait.until { answers.sleeping == 1 }
            if takingOver {
                answers.step()
                await TestWait.until { answers.sleeping == 1 }
            }
            await stopped.pipeline.stopAndRestoreVolume()
            answers.step()
            #expect(await starting.value == false)
            await stopped.pipeline.eventsDelivered() // the monitor's queue has nothing left to do
            #expect(!stopped.processes.isObserving)
        }
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
