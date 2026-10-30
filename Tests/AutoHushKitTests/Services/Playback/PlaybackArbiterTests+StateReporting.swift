import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - PlaybackState reporting

    @Test("a resume publishes that the music plays, not the paused state its check found")
    func resumePublishesMusicPlaying() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
    }

    @Test("publishes pausedByMonitor while a foreign source is active")
    func publishesPausedByMonitorWhileSourceActive() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        let state = await nextState(from: stateStream.stream)
        #expect(state == .pausedByMonitor)
    }

    @Test("refreshPlaybackState publishes what the player does: musicPlaying while it plays, musicIdle while it's paused",
          arguments: [(PlayerState.playing, PlaybackState.musicPlaying), (.paused, .musicIdle)])
    func refreshPublishesPlayerState(player state: PlayerState, published: PlaybackState) async {
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: MockMusicPlayer(state: state), stream: stateStream)

        await arbiter.refreshPlaybackState()

        #expect(await nextState(from: stateStream.stream) == published)
    }

    @Test("a report from the player's observer that comes while refreshPlaybackState asks the player stands: it's newer than the answer")
    func reportDuringRefreshStands() async {
        let player = MockMusicPlayer(state: .paused)
        let answers = ManualSleep()
        await player.setBeforeStateAnswer { await answers.sleep(.zero) }
        let arbiter = makeArbiter(player: player)
        let refreshing = Task { await arbiter.refreshPlaybackState() }
        await TestWait.until { answers.sleeping == 1 } // its answer says paused
        await arbiter.handlePlayerStateChange(.playing) // the user played it since
        answers.step()
        _ = await refreshing.value
        #expect(await arbiter.playerState == .playing)
    }

    // MARK: - Player state notifications / user-intent protection

    @Test("user resuming the player while a source plays clears pausedByUs and publishes musicPlaying")
    func playerPlayingNotificationClearsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream)  // drain .pausedByMonitor

        // User resumes the player; the player reports that it plays.
        await player.overrideState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
        // The player plays alongside the other app; we no longer hold it paused.
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)

        // When the source stops, the arbiter must not touch the player.
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the player quitting or stopping while we hold it paused clears pausedByUs, so nothing is resumed later",
          arguments: [PlayerState.notRunning, .stopped])
    func playerGoneClearsPausedByUs(_ reported: PlayerState) async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor

        await player.overrideState(reported)
        await arbiter.handlePlayerStateChange(reported)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0)
    }

    @Test("the Paused notification caused by our own pause keeps pausedByUs")
    func ownPauseNotificationKeepsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 1)
    }

    @Test("a stale report that the player plays doesn't end our pause while it's still paused")
    func staleReportKeepsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        #expect(await player.state == .paused)
        // Right after our pause, the player reports its previous state, then the new one.
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.handlePlayerStateChange(.paused)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
    }

    @Test("when the player doesn't answer, a report that it plays ends our pause")
    func unansweredReportEndsPausedByUs() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.waitForPause()
        await player.setUnansweredStateQueries(1)
        await arbiter.handlePlayerStateChange(.playing)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 0)
    }

    @Test("when the player doesn't answer, its report that it plays stands: the music shows as playing")
    func unansweredReportStands() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        _ = await nextState(from: stateStream.stream) // drain .pausedByMonitor
        await player.setUnansweredStateQueries(1)
        await arbiter.handlePlayerStateChange(.playing)

        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
    }

    @Test("an unknown player state is ignored and the resume still happens")
    func unknownStateIsIgnored() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.handlePlayerStateChange(.unknown)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await arbiter.waitUntilIdle()

        #expect(await player.playCallCount == 1)
    }

    @Test("status updates from notifications do not query the player through Apple events")
    func notificationsDoNotQueryPlayer() async {
        let player = MockMusicPlayer(state: .paused)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handlePlayerStateChange(.paused)
        #expect(await nextState(from: stateStream.stream) == .musicIdle)

        #expect(await player.stateQueryCount == 0)
    }

    // MARK: - The player playing on another device

    @Test("does not pause the player while it plays on another device")
    func doesNotPauseRemotePlayback() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)

        #expect(await player.pauseCallCount == 0)
        #expect(await player.stateQueryCount == 0)
    }

    @Test("pauses again once playback is back on this Mac")
    func pausesAfterPlaybackReturns() async {
        let player = MockMusicPlayer(state: .playing)
        let arbiter = makeArbiter(player: player)

        await arbiter.handleLocalPlaybackChange(false)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await arbiter.handleLocalPlaybackChange(true)
        await arbiter.sourceChanged("com.apple.Safari", playing: true)

        #expect(await player.pauseCallCount == 1)
    }

    @Test("publishes playingElsewhere while the player plays on another device")
    func publishesPlayingElsewhere() async {
        let player = MockMusicPlayer(state: .playing)
        let stateStream = StateStream()
        let arbiter = makeArbiterWithStream(player: player, stream: stateStream)

        await arbiter.handlePlayerStateChange(.playing)
        #expect(await nextState(from: stateStream.stream) == .musicPlaying)
        await arbiter.handleLocalPlaybackChange(false)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        #expect(await nextState(from: stateStream.stream) == .playingElsewhere)
    }
}
