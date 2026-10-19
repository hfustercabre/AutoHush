import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Filtering: excluded sources must not trigger pause

    @Test("the player's own audio and system audio daemons never pause it", arguments: [
        TestPlayer.bundleID,
        "com.apple.coreaudiod",
        "com.apple.audio.SandboxHelper",
        "com.apple.audio.UISoundsServer",
    ])
    func ignoresOwnAndSystemAudio(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    // MARK: - Pause behaviour

    /// Any other app alike: which apps count is AppConfiguration's (`isMediaSource`).
    @Test("pauses the player when another app starts playing", arguments: [
        "org.videolan.vlc",
        "com.example.somerandomplayer", // an app AutoHush knows nothing about
    ])
    func pausesForAnotherApp(sourceID: String) async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged(sourceID, playing: true)

        #expect(await player.pauseCallCount == 1)
        #expect(await player.state == .paused)
    }

    @Test("does not pause the player when it is already paused")
    func doesNotPauseAlreadyPaused() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
    }

    @Test("a player heard while it says it's paused (a web app's ad) is muted, and played again when the other app stops")
    func mutesPlayerHeardWhilePaused() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.commandLog == ["mute"])
        #expect(await player.pauseCallCount == 0)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog == ["mute", "play"])
    }

    @Test("a paused player that is silent is left alone, and not played afterwards")
    func leavesSilentPausedPlayer() async {
        let player = MockMusicPlayer(state: .paused)
        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.commandLog.isEmpty)
    }

    @Test("a player that isn't playing on this Mac isn't asked to mute, nor one that can't mute")
    func doesNotMuteRemotePlayer() async {
        let player = MockMusicPlayer(state: .paused)
        await player.setPlaysAnyway(true)
        let plain = makeArbiter(player: player)
        await plain.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 0)

        let arbiter = PlaybackArbiter(player: MockMutingMusicPlayer(player), configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())
        await arbiter.handleLocalPlaybackChange(false)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await player.muteIfPlayingAnywayCount == 0)
        #expect(await player.commandLog.isEmpty)
    }

    @Test("does not issue duplicate pause calls for repeated start events from the same source")
    func doesNotDuplicatePauseCalls() async {
        let player = MockMusicPlayer()
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
    }

    @Test("a pause that throws is a failed press, unless the player's controls are still being learned (a web app)",
          arguments: [false, true])
    func pauseErrorIsTolerated(stillLearning: Bool) async {
        let player = MockMusicPlayer(failPauseWith: stillLearning ? MusicPlayerError.stillLearning : StubError.failed)
        let states = Locked<[PlaybackState]>([])
        let failures = Locked<[MusicPlayerError?]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) },
                                      onPauseFailure: { failures.append($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 1)
        if stillLearning {
            #expect(failures.value.isEmpty)
            #expect(!states.value.contains(.pauseFailed))
        } else {
            #expect(failures.value == [.playerCommandFailed(.pressFailed)]) // an error of no kind AutoHush knows
            #expect(states.value.last == .pauseFailed)
        }
    }

    @Test("a pause that fails while another app plays says why, until the app stops")
    func failedPauseReported() async {
        let player = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.buttonDisabled))
        let states = Locked<[PlaybackState]>([])
        let failures = Locked<[MusicPlayerError?]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPlaybackStateChange: { states.append($0) },
                                      onPauseFailure: { failures.append($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(states.value.last == .pauseFailed)
        #expect(failures.value == [.playerCommandFailed(.buttonDisabled)])

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { states.value.last == .musicPlaying }
        #expect(states.value.last == .musicPlaying)
        #expect(failures.value == [.playerCommandFailed(.buttonDisabled), nil])
    }

    /// What ends a failed pause, for `failedPauseOver`.
    enum FailedPauseEnd: CaseIterable {
        case laterPauseWorks, userPauses, playsElsewhere, autoPauseOff, macSleeps
    }

    @Test("a failed pause is over once a later one works, the user pauses the music, it plays on another device, Auto-Pause goes off or the Mac sleeps",
          arguments: FailedPauseEnd.allCases)
    func failedPauseOver(end: FailedPauseEnd) async {
        let player = MockMusicPlayer(failPauseWith: MusicPlayerError.playerCommandFailed(.pressFailed))
        let failures = Locked<[MusicPlayerError?]>([])
        let arbiter = PlaybackArbiter(player: player, configuration: .testing, debounceScheduler: ManualDebounceScheduler(),
                                      onPauseFailure: { failures.append($0) })

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        switch end {
        case .laterPauseWorks:
            await player.setFailPause(nil)
            await arbiter.sourceChanged("com.apple.Safari", playing: true) // a second app: this pause works
            #expect(await player.pauseCallCount == 2)
        case .userPauses: await arbiter.handlePlayerStateChange(.paused)
        case .playsElsewhere: await arbiter.handleLocalPlaybackChange(false)
        case .autoPauseOff: await arbiter.setAutoPauseEnabled(false)
        case .macSleeps: await arbiter.setAsleep(true)
        }
        #expect(failures.value == [.playerCommandFailed(.pressFailed), nil])
    }
}
