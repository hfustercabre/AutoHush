import CoreAudio
import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// The pipeline wired as the app wires it, with stand-ins for what it reads
/// from macOS: an app starting to play reaches the arbiter, which pauses the
/// player.
@MainActor
@Suite("MonitoringPipeline", .waitsTimeLimit)
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
        let outputs = MockOutputDisconnects()
        let configuration: AppConfiguration
        let pipeline: MonitoringPipeline

        /// `stopGrace`: how long a playing app must be quiet to count as stopped.
        @MainActor
        /// `playerMute`: mutes the player in place of a pause, as the app's
        /// readers do by default (it can't mute the stand-in player).
        init(player: any MusicPlayer, detectionMethod: DetectionMethod = .audioLevels,
             stopGrace: TimeInterval = TimingSettings.defaults.stopGrace, pausesOnOutputDisconnect: Bool = false,
             playerMute: @escaping @Sendable (String, @escaping @Sendable () -> Bool) -> (any PlayerMuting)? = {
                 ProcessPlayerMute(bundleID: $0, tapsAllowed: $1)
             }) {
            var configuration = MonitoringPipelineTests.configuration(stopGrace: stopGrace)
            configuration.pausesOnOutputDisconnect = pausesOnOutputDisconnect
            self.configuration = configuration
            processes.processes = [MonitoringPipelineTests.playerProcess, MonitoringPipelineTests.otherApp]
            // The player's stand-in sound follows it: heard while it plays, silent once paused.
            if let mock = player as? MockMusicPlayer {
                meter.follow(MonitoringPipelineTests.playerProcess.objectID, playing: mock.plays, peak: 0.3)
            }
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
                               powerAssertions: MockPowerAssertions(), outputDisconnects: outputs,
                               playerMute: playerMute,
                               playerInput: { _ in { _ in true } }), // every start the user's
                onStatusUpdate: { updates.all.append($0) }
            )
        }

        /// The other app's sound comes on, loud, as the audio server announces
        /// it; the player is heard too.
        func otherAppPlays() async {
            meter.peaks = [MonitoringPipelineTests.otherApp.objectID: 0.5, MonitoringPipelineTests.playerProcess.objectID: 0.3]
            await TestWait.until { processes.isObserving }
            processes.triggerChange()
        }
    }

    @Test("with Pause on disconnect, the output going away reaches the arbiter, which pauses the player; stopped, the pipeline stops watching")
    func outputDisconnectPausesPlayer() async {
        let player = MockMusicPlayer(state: .playing)
        let setup = Setup(player: player, pausesOnOutputDisconnect: true)
        await setup.pipeline.start()
        #expect(setup.outputs.isWatching)
        setup.outputs.disconnect()
        await TestWait.until { await player.pauseCallCount == 1 }
        setup.pipeline.stop()
        #expect(!setup.outputs.isWatching)
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

    @Test("each command reaches the arbiter: held resumes, Auto-Pause, new timings, an app ignored and counting again, the user's own pause and play, without waiting in real time")
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
        let told = setup.updates.playback.count
        setup.pipeline.holdResumes(true)
        setup.pipeline.setAutoPauseEnabled(false)
        await TestWait.until { await mock.playCallCount > 0 || setup.updates.playback.count >= told + 3 }
        #expect(await mock.playCallCount == 0)
        setup.pipeline.holdResumes(false)
        await TestWait.until { await mock.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        #expect(await mock.playCallCount == 1)
        // Measured again as it plays, so the next pause hears it.
        setup.processes.triggerChange()
        await setup.pipeline.eventsDelivered()

        // Shorter timings, then Auto-Pause back on: paused again for the app still playing.
        var shorter = setup.configuration
        shorter.sourceStopGrace = 0
        setup.pipeline.setConfiguration(shorter)
        setup.pipeline.setAutoPauseEnabled(true)
        await TestWait.until { setup.updates.playback.last == .pausedByMonitor }
        #expect(await mock.pauseCallCount == 2)

        // The app ignored, it no longer counts: the pause ends and the music comes back.
        setup.pipeline.setIgnoredSources([Self.otherApp.bundleID])
        await TestWait.until { await mock.playCallCount == 2 }
        await setup.pipeline.waitForResume()
        // The user pauses it: its observer tells the arbiter, so once the app
        // counts again nothing is paused or played: the pause is theirs.
        await mock.userSets(.paused)
        await TestWait.until { setup.updates.playback.last == .musicIdle }
        setup.pipeline.setIgnoredSources([])
        await setup.pipeline.settled()
        #expect(await mock.pauseCallCount == 2)
        #expect(await mock.playCallCount == 2)

        // The user plays it while the app is ignored; the app counting again,
        // it can't be paused: the menu hears why.
        await mock.setFailPause(MusicPlayerError.playerCommandFailed(.pressIgnored))
        setup.pipeline.setIgnoredSources([Self.otherApp.bundleID])
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

    @Test("AntiDot mode, chosen while the monitoring runs, stops the player's mute in place of a pause; measuring allows it again",
          arguments: [DetectionMethod.playbackSignals, .openStreams])
    func antiDotModeStopsPlayerMute(antiDot: DetectionMethod) async {
        let allowed = Locked<(@Sendable () -> Bool)?>(nil)
        let setup = Setup(player: MockMusicPlayer(), playerMute: { _, tapsAllowed in
            allowed.value = tapsAllowed
            return FakeMute(allowed: tapsAllowed)
        })
        #expect(allowed.value?() == true)
        setup.pipeline.setDetectionMethod(antiDot)
        #expect(allowed.value?() == false)
        setup.pipeline.setDetectionMethod(.audioLevels)
        #expect(allowed.value?() == true)
        setup.pipeline.stop()
    }
}
