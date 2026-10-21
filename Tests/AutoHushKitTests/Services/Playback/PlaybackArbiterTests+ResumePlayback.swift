import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

// Resume playback (Settings → Detection) turned off: AutoHush only pauses
// the music; once the apps stop, the pause is the user's and stays.
extension PlaybackArbiterTests {
    /// The test configuration with Resume playback off.
    private var noResume: AppConfiguration {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        return configuration
    }

    @Test("with Resume playback off, the music paused for an app stays paused once it stops, said so, and the next app finds nothing to pause")
    func staysPausedWithoutResume() async {
        let player = MockMusicPlayer()
        let states = Locked<[PlaybackState]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: noResume, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) })
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(states.value.last == .pausedByMonitor)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
        #expect(states.value.last == .musicIdle) // no longer our pause

        await arbiter.sourceChanged("com.apple.Safari", playing: true)
        await arbiter.sourceChanged("com.apple.Safari", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.pauseCallCount == 1)
        #expect(await player.playCallCount == 0)
    }

    @Test("with Resume playback off, turning Auto-Pause off during the pause leaves the music paused")
    func autoPauseOffWithoutResume() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: noResume)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setAutoPauseEnabled(false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("Resume playback turned back on before the apps stop: the music resumes as before")
    func resumeTurnedBackOn() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player, configuration: noResume)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.setConfiguration(.testing)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("with Resume playback off, a mute standing in for the pause (a web app's ad) is turned into a real pause once the apps stop")
    func noResumeEndsMute() async {
        let player = MockMusicPlayer()
        await player.overrideState(.paused)
        await player.setPlaysAnyway(true)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: noResume,
                                      debounceScheduler: ManualDebounceScheduler())
        await arbiter.sourceChanged("org.videolan.vlc", playing: true) // muted for it
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog.contains("forgetPause"))
        #expect(await player.playCallCount == 0)
    }

    @Test("Resume playback turned off while a resume tries again puts the Mac's lowered volume back, and the music stays paused")
    func resumeOffPutsBackLevel() async {
        let player = MockMusicPlayer()
        let scheduler = ManualDebounceScheduler()
        let leveler = RecordingVolumeLeveler()
        let arbiter = makeLevelingArbiter(player, leveler: leveler, scheduler: scheduler)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await player.setFailPlay(MusicPlayerError.playerCommandFailed(.pressIgnored))
        await arbiter.sourceChanged("org.videolan.vlc", playing: false) // lowers, fails, waits to try again
        await TestWait.until { scheduler.scheduledDelays == [PlaybackArbiter.resumeRetryDelay] }
        #expect(leveler.log == ["lower -6.0"])

        var configuration = noResume
        configuration.levelsMusic = true
        await arbiter.setConfiguration(configuration)
        await player.setFailPlay(nil)
        await scheduler.completeNext()
        await TestWait.until { leveler.log.count == 2 }
        await arbiter.waitUntilIdle()
        #expect(leveler.log == ["lower -6.0", "restore now"])
        #expect(await player.playCallCount == 1) // only the failed try
    }
}
