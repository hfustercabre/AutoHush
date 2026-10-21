import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

// Pause on disconnect (Settings → Detection): the output in use
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
                               onPlaybackStateChange: { states.append($0) })
    }

    @Test("playing, the output going away pauses the music at once, without a fade, says it isn't playing, and nothing resumes it")
    func disconnectPausesAtOnce() async {
        let player = MockMusicPlayer(state: .playing)
        let steps = FadeSteps()
        let states = Locked<[PlaybackState]>([])
        let arbiter = await disconnectArbiter(player, steps: steps, states: states)
        await arbiter.handleOutputDisconnected()
        #expect(await player.pauseCallCount == 1)
        #expect(await steps.count == 1) // only the wait before the volume is set back
        #expect(states.value.last == .musicIdle)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("a pause of AutoHush's is the user's once the output goes away, said so at once: the music stays paused when the apps stop")
    func disconnectKeepsPause() async {
        let player = MockMusicPlayer(state: .playing)
        let states = Locked<[PlaybackState]>([])
        let arbiter = await disconnectArbiter(player, states: states)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(states.value.last == .pausedByMonitor)
        await arbiter.handleOutputDisconnected()
        #expect(states.value.last == .musicIdle) // VLC still plays: no longer our pause
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(await player.pauseCallCount == 1)
    }

    @Test("a pause fading out as the output goes away is forgotten once it's done: the music stays paused")
    func disconnectDuringFadeOut() async {
        let player = MockMusicPlayer(state: .playing)
        let steps = FadeSteps(holdingAt: 2)
        let arbiter = await disconnectArbiter(player, steps: steps)
        await arbiter.handleSourceChange(sourceID: "org.videolan.vlc", isPlaying: true) // its pause runs on its own
        await TestWait.until { await steps.count == 2 } // fading out
        await arbiter.handleOutputDisconnected()
        await steps.letGo(2)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
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
        await arbiter.sourceChanged("org.videolan.vlc", playing: true) // muted for it
        await arbiter.handleOutputDisconnected()
        #expect(await player.commandLog.contains("forgetPause"))
    }

    @Test("music playing with the Mac's volume lowered (Level the volume) gets it back as the output goes away")
    func disconnectPutsBackLevel() async {
        let player = MockMusicPlayer(state: .playing)
        let leveler = RecordingVolumeLeveler()
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        configuration.pausesOnOutputDisconnect = true
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false) // resumed, lowered 6 dB
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        await arbiter.handleOutputDisconnected()
        #expect(leveler.log == ["lower -6.0", "restore now"])
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
