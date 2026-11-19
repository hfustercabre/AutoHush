import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

// Pause on disconnect (Settings → Behavior): the output in use
// going away pauses the music at once and for good.
extension PlaybackArbiterTests {
    /// An arbiter for `player`, at volume 60 so it fades, its fades' waits
    /// counted (and held) by `steps`; the switch `on`, Auto-Pause `autoPause`.
    private func disconnectArbiter(_ player: MockMusicPlayer, steps: FadeSteps = FadeSteps(), on: Bool = true,
                                   autoPause: Bool = true, states: Locked<[PlaybackState]> = Locked([])) async -> PlaybackArbiter {
        await player.setVolumeLevel(60)
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = on
        return PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                               fadeSleep: { _ in await steps.step() }, autoPauseEnabled: autoPause,
                               onStatusUpdate: statuses(playback: { states.append($0) }))
    }

    @Test("playing, the output going away pauses the music at once, without a fade, says it isn't playing, and nothing resumes it")
    func disconnectPausesAtOnce() async {
        let player = MockMusicPlayer(state: .playing)
        let steps = FadeSteps()
        let states = Locked<[PlaybackState]>([])
        let arbiter = await disconnectArbiter(player, steps: steps, states: states)
        await arbiter.handleOutputDisconnected()
        #expect(await player.pauseCallCount == 1)
        #expect(await player.uncoveredPauses == 1) // no mute will stand in: a player's backups at once
        #expect(await steps.count == 1) // only the wait before the volume is set back
        #expect(states.value.last == .musicIdle)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a pause of AutoHush's is the user's once the output goes away, said so at once: the music stays paused when the apps stop")
    func disconnectKeepsPause() async {
        let player = MockMusicPlayer(state: .playing)
        let states = Locked<[PlaybackState]>([])
        let arbiter = await disconnectArbiter(player, states: states)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(states.value.last == .pausedByMonitor)
        await arbiter.handleOutputDisconnected()
        #expect(states.value.last == .musicIdle) // Viewer still plays: no longer our pause
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("a pause fading out as the output goes away pauses where it got to, not fading on, and is forgotten: the music stays paused")
    func disconnectDuringFadeOut() async {
        let player = MockMusicPlayer(state: .playing)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await disconnectArbiter(player, steps: steps)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 } // fading out: 10 steps of 0.1 s in all
        await arbiter.handleOutputDisconnected()
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(await steps.count < 10) // the fade's other 8 steps never came
        await arbiter.sourceChanged("org.example.viewer", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a pause fading out as the output goes away, refused, is tried once more uncovered (every backup) before its mute is lifted; taken, it's paused and said so (K1-1 of 11-11, R2)",
          arguments: [false, true])
    func refusedDisconnectDuringFadeOutTriesUncovered(backupsPause: Bool) async {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await player.setBackupsPause(backupsPause)
        let steps = FadeSteps(holdingAt: 2), mute = FakeMute()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() }, playerMute: mute)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 }
        await arbiter.handleOutputDisconnected()
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.uncoveredPauses == 1) // tried with every backup
        #expect(mute.unmuteCount == mute.muteCount) // no mute left standing
        #expect(await arbiter.pausedByUs == false)
        #expect(await arbiter.playerState == (backupsPause ? .paused : .playing)) // shown as it is
    }

    @Test("a pause fading out as the output goes away, its real pause going through without taking (the player plays on), stays shown as playing once its mute is lifted (engine-2)")
    func ignoredDisconnectDuringFadeOutPlaysOn() async {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        await player.setIgnoredPresses(1000) // each pause goes through, none takes
        let steps = FadeSteps(holdingAt: 2), mute = FakeMute()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() }, playerMute: mute)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 }
        await arbiter.handleOutputDisconnected()
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.uncoveredPauses >= 1) // tried with every backup
        #expect(mute.unmuteCount == mute.muteCount) // no mute left standing
        #expect(await arbiter.playerState == .playing) // not said paused: it plays on
    }

    @Test("a pause fading out as the output goes away, refused after the last app stopped, is tried once more uncovered (every backup): taken, it's paused; refused, it plays on at the user's volume (diff-kit-1)",
          arguments: [false, true])
    func refusedDisconnectAfterAppsStopTriesUncovered(backupsPause: Bool) async {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await player.setBackupsPause(backupsPause)
        let steps = FadeSteps(holdingAt: 2), mute = FakeMute()
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in await steps.step() }, playerMute: mute)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 }
        await arbiter.handleOutputDisconnected() // cut short: it pauses where it got to
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: false) // the video stops too
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.uncoveredPauses == 1) // tried with every backup
        #expect(mute.muteCount == 0) // no app left to mute it for
        #expect(await player.state == (backupsPause ? .paused : .playing))
        #expect(await arbiter.playerState == (backupsPause ? .paused : .playing)) // shown as it is
        #expect(await arbiter.pausedByUs == false) // the user's: nothing resumes it
        #expect(await player.playCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("a fade-out called off (the app stopped), its music not coming back up yet as the output goes away, is paused at once, not faded in on the next one (diff-kit-2)")
    func disconnectBeforeComeback() async {
        let player = MockMusicPlayer(state: .playing)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await disconnectArbiter(player, steps: steps)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 }
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: false) // called off within the step
        await arbiter.handleOutputDisconnected()
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(await player.state == .paused)
        #expect(await player.playCallCount == 0)
        #expect(await player.volumeLevel == 60)
    }

    @Test("a fade-out's pause refused leaves the volume down while the mute in its place is made, then sets it back behind the mute, or, unmutable, as it plays on: no blip at full volume (K1-3 of 11-11)",
          arguments: [true, false])
    func refusedFadeOutRestoresBehindMute(mutes: Bool) async {
        let player = MockMusicPlayer(state: .playing)
        await player.setVolumeLevel(60)
        await player.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        let mute = FakeMute(works: mutes), atMute = Locked<Int?>(nil)
        mute.whileMuting = { atMute.value = await player.volumeLevel ?? 60 }
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, playerMute: mute)
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.waitUntilIdle()
        #expect(mute.muteCount == 1)
        #expect((atMute.value ?? 60) < 60) // still down while the mute was made
        #expect(await player.volumeLevel == 60) // then set back
        #expect(await arbiter.pausedByUs == mutes)
    }

    @Test("music coming back up after a fade-out called off (the app stopped within it) is paused at once as the output goes away, not faded in on the next one")
    func disconnectDuringComeback() async {
        let player = MockMusicPlayer(state: .playing)
        // Called off at its second step, the fade-out comes back up in two: steps 3 and 4.
        let steps = FadeSteps(holdingAt: 2, 4)
        let arbiter = await disconnectArbiter(player, steps: steps)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 }
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: false) // the music comes back up
        await steps.letGo(2)
        await TestWait.until { await steps.count == 4 }
        await arbiter.handleOutputDisconnected()
        await steps.letGo(4)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(await player.state == .paused)
        #expect(await player.playCallCount == 0)
    }

    @Test("a mute standing in for the pause (a web app's ad) is turned into a real pause once the output goes away")
    func disconnectEndsMute() async {
        let player = MockMusicPlayer()
        await player.overrideState(.paused)
        await player.setPlaysAnyway(true)
        var configuration = AppConfiguration.testing
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: configuration,
                                      debounceScheduler: ManualDebounceScheduler())
        await arbiter.sourceChanged("org.example.viewer", playing: true) // muted for it
        await arbiter.handleOutputDisconnected()
        #expect(await player.commandLog.contains("forgetPause"))
    }

    @Test("music playing with the Mac's volume lowered (Level the volume) leaves it lowered as the output goes away: nothing raises it")
    func disconnectKeepsLevel() async {
        let player = MockMusicPlayer(state: .playing)
        let leveler = RecordingVolumeLeveler()
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false) // resumed, lowered 6 dB
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await arbiter.handleOutputDisconnected()
        #expect(leveler.log == ["lower -6.0"])
    }

    @Test("music playing with the Mac's volume lowered (Level the volume) keeps it lowered when its pause fails as the output goes away")
    func failedDisconnectPauseKeepsLevel() async {
        let player = MockMusicPlayer(state: .playing)
        let leveler = RecordingVolumeLeveler()
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        await arbiter.sourceChanged("org.example.viewer", playing: true)
        await arbiter.sourceChanged("org.example.viewer", playing: false) // resumed, lowered 6 dB
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await player.setFailPause(StubError.failed)
        await arbiter.handleOutputDisconnected()
        #expect(leveler.log == ["lower -6.0"])
    }

    @Test("with the switch off, or Auto-Pause off, the output going away changes nothing", arguments: [(false, true), (true, false)])
    func disconnectIgnored(on: Bool, autoPause: Bool) async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = await disconnectArbiter(player, on: on, autoPause: autoPause)
        await arbiter.handleOutputDisconnected()
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 0)
    }

    @Test("a player playing on another device isn't paused when this Mac's output goes away")
    func disconnectLeavesRemotePlayback() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = await disconnectArbiter(player)
        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.handleOutputDisconnected()
        #expect(await player.pauseCallCount == 0)
    }
}
