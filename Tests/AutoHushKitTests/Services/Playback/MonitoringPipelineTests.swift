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
    private nonisolated static let otherApp = AudioProcessInfo(objectID: 2, bundleID: "org.example.viewer", pid: 999_999)

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
            var configuration = AppConfiguration.testTicksOnly
            configuration.sourceStopGrace = stopGrace
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
                readers: .standIns(processes: processes, levelMeter: meter, outputDisconnects: outputs, playerMute: playerMute),
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
        await TestWait.until { setup.updates.activeSources.last?.map(\.id) == ["org.example.viewer"] }
        #expect(setup.pipeline.activeAudioReport() == [.init(id: "org.example.viewer", state: .playing, evidence: .level(0.5))])

        setup.pipeline.setIgnoredSources(["org.example.viewer"])
        await TestWait.until { await player.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        #expect(await player.playCallCount == 1)
        setup.pipeline.stop()
    }

    /// Another app playing paused the player, which `setup` started.
    private func pausedForOtherApp(_ setup: Setup, _ mock: MockMusicPlayer) async {
        await setup.pipeline.start()
        await setup.otherAppPlays()
        await TestWait.until { setup.updates.playback.last == .pausedByMonitor }
        #expect(await mock.pauseCallCount == 1)
    }

    /// Auto-Pause off brings the music back, though the app still plays;
    /// measured again as it plays, so the next pause hears it.
    private func autoPauseOff(_ setup: Setup, _ mock: MockMusicPlayer) async {
        setup.pipeline.setAutoPauseEnabled(false)
        await TestWait.until { await mock.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        setup.processes.triggerChange()
        await setup.pipeline.eventsDelivered()
    }

    @Test("held resumes reach the arbiter: nothing resumes, not even with Auto-Pause off, until they're let go")
    func heldResumesReachArbiter() async {
        let mock = MockMusicPlayer(state: .playing)
        let setup = Setup(player: mock)
        await pausedForOtherApp(setup, mock)
        setup.pipeline.holdResumes(true)
        setup.pipeline.setAutoPauseEnabled(false)
        await setup.pipeline.settled()
        #expect(await mock.playCallCount == 0)
        setup.pipeline.holdResumes(false)
        await TestWait.until { await mock.playCallCount == 1 }
        setup.pipeline.stop()
    }

    @Test("Auto-Pause reaches the arbiter: off, the music comes back though the app still plays; on again, it's paused again")
    func autoPauseReachesArbiter() async {
        let mock = MockMusicPlayer(state: .playing)
        let setup = Setup(player: mock, stopGrace: 0)
        await pausedForOtherApp(setup, mock)
        await autoPauseOff(setup, mock)
        setup.pipeline.setAutoPauseEnabled(true)
        await TestWait.until { await mock.pauseCallCount == 2 }
        setup.pipeline.stop()
    }

    @Test("new timings reach the arbiter: Auto-Pause back on pauses as soon as they say, not after the old minute")
    func timingsReachArbiter() async {
        let mock = MockMusicPlayer(state: .playing)
        // A minute: Auto-Pause back on pauses only after it, unless shorter timings reached the arbiter.
        let setup = Setup(player: mock, stopGrace: 60)
        await pausedForOtherApp(setup, mock)
        await autoPauseOff(setup, mock)
        var shorter = setup.configuration
        shorter.sourceStopGrace = 0
        setup.pipeline.setConfiguration(shorter)
        setup.pipeline.setAutoPauseEnabled(true)
        await TestWait.until { await mock.pauseCallCount == 2 }
        setup.pipeline.stop()
    }

    @Test("the user's pause reaches the arbiter: once the app ignored counts again, nothing is paused or played, the pause is theirs")
    func usersPauseReachesArbiter() async {
        let mock = MockMusicPlayer(state: .playing)
        let setup = Setup(player: mock)
        await pausedForOtherApp(setup, mock)
        // The app ignored, it no longer counts: the pause ends and the music comes back.
        setup.pipeline.setIgnoredSources([Self.otherApp.bundleID])
        await TestWait.until { await mock.playCallCount == 1 }
        await setup.pipeline.waitForResume()
        // The user pauses it: its observer tells the arbiter.
        await mock.userSets(.paused)
        await TestWait.until { setup.updates.playback.last == .musicIdle }
        setup.pipeline.setIgnoredSources([])
        await setup.pipeline.settled()
        #expect(await mock.pauseCallCount == 1)
        #expect(await mock.playCallCount == 1)
        setup.pipeline.stop()
    }

    @Test("the user's play reaches the arbiter: played while the app is ignored, it can't be paused once the app counts again, and the menu hears why")
    func usersPlayReachesArbiter() async {
        let mock = MockMusicPlayer(state: .paused)
        await mock.setFailPause(MusicPlayerError.playerCommandFailed(.pressIgnored))
        let setup = Setup(player: mock)
        await setup.pipeline.start()
        setup.pipeline.setIgnoredSources([Self.otherApp.bundleID])
        await setup.otherAppPlays()
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

    @Test("a play its observer reports while the pipeline asks the player's state, as it starts, stands: the monitor knows it plays")
    func reportWhileStartingStands() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setUnansweredStateQueries(1) // busy as it starts: no answer
        let answers = ManualSleep()
        await player.setBeforeStateAnswer { await answers.sleep(.zero) }
        let setup = Setup(player: player)
        let starting = Task { await setup.pipeline.start() }
        await TestWait.until { answers.sleeping == 1 }
        await player.setBeforeStateAnswer(nil)
        await player.userSets(.playing) // its observer says so
        answers.step()
        _ = await starting.value
        let monitor = setup.pipeline.monitor
        #expect(await monitor.queue.run { monitor.playerPlayingSince != nil })
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
