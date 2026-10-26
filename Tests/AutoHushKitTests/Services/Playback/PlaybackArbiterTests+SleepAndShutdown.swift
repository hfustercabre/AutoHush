import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Sleep

    @Test("music paused when the Mac goes to sleep stays paused after it wakes")
    func pauseForgottenInSleep() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let arbiter = makeArbiter(player: player, scheduler: scheduler)

        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: true)
        #expect(await player.pauseCallCount == 1)
        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: false) // its sound stops as the Mac falls asleep
        await arbiter.setAsleep(false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty)
        #expect(await player.state == .paused)
    }

    @Test("the Mac going to sleep during our pause says at once that the pause is no longer ours")
    func sleepPublishesForgottenPause() async {
        let states = Locked<[PlaybackState]>([])
        let told = Locked<[Bool]>([])
        let needs = Locked<[Bool]>([])
        let arbiter = PlaybackArbiter(player: MockMusicPlayer(), configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onStatusUpdate: statuses(playback: { states.append($0) }),
                                      onAudioLevelsNeededChange: { needs.append($0) },
                                      onPausedByUsChange: { told.append($0) })

        await arbiter.sourceChanged("com.apple.QuickTimePlayerX", playing: true)
        #expect(states.value.last == .pausedByMonitor)
        await arbiter.setAsleep(true)
        #expect(told.value == [true, false])
        #expect(needs.value == [true, false])
        #expect(states.value.last == .musicIdle)
    }

    @Test("a sleep that arrives after a later wake is ignored")
    func lateSleepIgnored() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(false, change: 2) // the wake, told second, arrives first
        await arbiter.setAsleep(true, change: 1)  // the sleep, told first, arrives late
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 1) // awake: it pauses
    }

    @Test("numbered sleeps and wakes that arrive in order apply: nothing pauses during the sleep, and an app pauses the music once awake")
    func numberedSleepAndWakeApply() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(true, change: 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 0) // asleep
        await arbiter.setAsleep(false, change: 2)
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("a pause handed over while the Mac sleeps is forgotten too")
    func handoverForgottenInSleep() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(true)
        await arbiter.takeOverPause()
        await arbiter.setAsleep(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("nothing is paused while the Mac sleeps; an app still playing once it's awake pauses the music")
    func noPauseInSleep() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.pauseCallCount == 0)

        await arbiter.setAsleep(false)
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 1)
    }

    @Test("a mute in place of a pause is forgotten once the Mac is awake, and not played again")
    func muteForgottenAfterSleep() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.commandLog == ["mute"])
        await arbiter.setAsleep(true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        #expect(await player.commandLog == ["mute"]) // told once awake, when it can act
        await arbiter.setAsleep(false)
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "forgetPause"])
    }

    @Test("a pause that ends after the Mac went to sleep is forgotten too: no resume once it's awake")
    func pauseFinishingInSleepForgotten() async {
        let player = MockMusicPlayer()
        await player.setVolumeLevel(60)
        let fading = Gate()
        let started = Gate()
        let arbiter = PlaybackArbiter(player: player, configuration: AppConfiguration(),
                                      debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await started.open(); await fading.wait() })

        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: true)
        await started.wait() // the fade-out is under way
        await arbiter.setAsleep(true)
        await fading.open()
        await arbiter.waitForPause()
        #expect(await player.pauseCallCount == 1)
        await arbiter.setAsleep(false)
        // Its sound stopped as the Mac fell asleep; the monitor reports it once awake.
        await arbiter.handleSourceChange(sourceID: "com.apple.QuickTimePlayerX", isPlaying: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.state == .paused)
    }

    /// A muting player whose check before muting says so on `started`, then
    /// waits for `gate`: the Mac can go to sleep meanwhile.
    private static func slowMuting(_ player: MockMusicPlayer, started: Gate, gate: Gate) async -> MockMutingMusicPlayer {
        let muting = MockMutingMusicPlayer(player)
        await muting.setBeforeMute {
            await started.open()
            await gate.wait()
        }
        return muting
    }

    @Test("a mute that comes after the Mac went to sleep is forgotten once it's awake")
    func muteFinishingInSleepForgotten() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let muting = Gate()
        let started = Gate()
        let arbiter = PlaybackArbiter(player: await Self.slowMuting(player, started: started, gate: muting),
                                      configuration: .testing, debounceScheduler: ManualDebounceScheduler())

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await started.wait() // it's being listened to
        await arbiter.setAsleep(true)
        await muting.open()
        await arbiter.waitForPause()
        #expect(await player.commandLog == ["mute"])
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await arbiter.setAsleep(false)
        await TestWait.until { await player.commandLog.count >= 2 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "forgetPause"])
    }

    @Test("a player muted just as the other app stopped, or Auto-Pause went off, while it was listened to is played again at once",
          arguments: [false, true])
    func everyAppStopsWhileMuting(autoPauseGoesOff: Bool) async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let muting = Gate()
        let started = Gate()
        let arbiter = PlaybackArbiter(player: await Self.slowMuting(player, started: started, gate: muting),
                                      configuration: .testing, debounceScheduler: ManualDebounceScheduler())

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await started.wait() // it's being listened to
        if autoPauseGoesOff {
            await arbiter.setAutoPauseEnabled(false)
        } else {
            await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        }
        await muting.open()
        await arbiter.waitForPause()
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "play"])
    }

    // MARK: - Shutdown

    @Test("shutdown calls off a resume under way")
    func shutdownCancelsPendingResume() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)
        let answer = Gate()

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        let pauseQueries = await player.stateQueryCount // its check, and its press's
        await player.setBeforeStateAnswer { await answer.wait() }
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: false)
        await TestWait.until { await player.stateQueryCount > pauseQueries } // the resume is asking the player
        await arbiter.shutdown()
        await answer.open()
        await arbiter.waitUntilIdle() // the resume it called off

        #expect(await player.playCallCount == 0)
    }

    @Test("a pause waiting for the apps to be measured again neither checks on the player nor mutes it once the arbiter is shut down")
    func shutdownCancelsPendingPause() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true) // heard while it says it's paused: a check would mute it
        let scheduler = ManualDebounceScheduler()
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: scheduler, autoPauseEnabled: false)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(true) // waits for VLC to be measured again
        await arbiter.shutdown()
        await scheduler.completeNext() // that wait ends
        await arbiter.waitUntilIdle()

        #expect(await player.stateQueryCount == 0)
        #expect(await player.commandLog.isEmpty)
    }

    @Test("a shut-down arbiter ignores new sources")
    func shutdownIgnoresNewSources() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.shutdown()
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    @Test("shutdown lifts a mute standing in for the pause: a mute, unlike a pause, can't be undone by the user")
    func shutdownLiftsMute() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true) // a web app's ad
        let muting = MockMutingMusicPlayer(player)
        let arbiter = PlaybackArbiter(player: muting, configuration: .testing, debounceScheduler: ManualDebounceScheduler())
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.commandLog == ["mute"])

        await arbiter.shutdown()
        #expect(await muting.releasedMutes == 1)
    }

    @Test("a mute that comes after monitoring stopped is lifted at once: nothing would ever lift it")
    func muteAfterShutdownLifted() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let gate = Gate()
        let started = Gate()
        let muting = await Self.slowMuting(player, started: started, gate: gate)
        let arbiter = PlaybackArbiter(player: muting, configuration: .testing, debounceScheduler: ManualDebounceScheduler())

        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true)
        await started.wait() // it's being listened to
        await arbiter.shutdown()
        await gate.open()
        await arbiter.waitForPause()
        #expect(await player.commandLog == ["mute"])
        #expect(await muting.releasedMutes == 1)
    }
}
