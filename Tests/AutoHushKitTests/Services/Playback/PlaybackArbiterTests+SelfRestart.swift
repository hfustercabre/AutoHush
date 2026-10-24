import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

extension PlaybackArbiterTests {
    // MARK: - Starting again by itself

    /// Stands in for muting the player's sound (`PlayerMuting`).
    final class FakeMute: PlayerMuting, @unchecked Sendable {
        // Read and written only under `lock`.
        private let lock = NSLock()
        private let works: Bool
        private var mutes = 0, unmutes = 0
        /// Runs while it mutes (the monitoring stopping meanwhile); set before any mute.
        var whileMuting: (@Sendable () async -> Void)?
        init(works: Bool = true) { self.works = works }
        var muteCount: Int { lock.withLock { mutes } }
        var unmuteCount: Int { lock.withLock { unmutes } }
        func mute() async -> Bool {
            await whileMuting?()
            return lock.withLock { mutes += 1; return works }
        }
        func unmute() async { lock.withLock { unmutes += 1 } }
    }

    /// An arbiter whose player VLC paused, with a clock, the user's last
    /// input `inputAgo` seconds before each look, and `mute`.
    private func pausedForVLC(_ player: MockMusicPlayer, clock: ManualClock, inputAgo: TimeInterval = 600,
                              hearing: Hearing = Hearing(true), mute: FakeMute? = FakeMute(), published: LastPublished,
                              configuration: AppConfiguration = .testing, mutedInstead: Locked<[Bool]>? = nil,
                              commanded: Locked<Int>? = nil) async -> PlaybackArbiter {
        let arbiter = PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: ManualDebounceScheduler(),
                                      clock: { clock.now }, onPlaybackStateChange: { published.set($0) },
                                      hearsPlayer: { hearing.ask() }, secondsSinceUserInput: { inputAgo },
                                      onMutedInsteadChange: { mutedInstead?.append($0) },
                                      onPlayerCommanded: { commanded?.increment() }, playerMute: mute)
        await arbiter.sourceChanged("org.videolan.vlc", playing: true)
        await TestWait.until { await player.pauseCallCount == 1 }
        await arbiter.waitUntilIdle()
        return arbiter
    }

    /// The player starts again, a second later.
    private func startsAgain(_ player: MockMusicPlayer, _ arbiter: PlaybackArbiter, clock: ManualClock) async {
        clock.advance(by: 1)
        await player.setState(.playing)
        await arbiter.handlePlayerStateChange(.playing)
    }

    @Test("a player that starts again by itself is paused again, twice, then muted until the apps stop, then unmuted, not played")
    func selfRestartPausedThenMuted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let mutedInstead = Locked<[Bool]>([])
        let arbiter = await pausedForVLC(player, clock: clock, mute: mute, published: published, mutedInstead: mutedInstead)
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 2)
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 3)
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 3)
        #expect(mute.muteCount == 1)
        #expect(mute.unmuteCount == 0) // muted until the apps stop
        #expect(published.state == .pausedByMonitor)
        #expect(mutedInstead.value == [true]) // the menu says Muted

        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        await arbiter.waitUntilIdle()
        #expect(await player.playCallCount == 0) // it plays already: only unmuted
        #expect(published.state == .musicPlaying)
        #expect(mutedInstead.value == [true, false])
    }

    @Test("a player the user played after the pause (a key pressed or a click since) is theirs, as before")
    func userRestartIsTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, inputAgo: 0.2, mute: mute, published: published)
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 1)
        #expect(mute.muteCount == 0)
        #expect(published.state == .musicPlaying)
    }

    @Test("a player starting again long after the pause is the user's, input or not")
    func lateRestartIsTheirs() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, published: published)
        clock.advance(by: PlaybackArbiter.selfRestartWindow)
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 1)
        #expect(published.state == .musicPlaying)
    }

    @Test("a player that starts again by itself, silently (the next muted trailer), is left alone, the pause still AutoHush's")
    func silentRestartLeftAlone() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let hearing = Hearing(true)
        let arbiter = await pausedForVLC(player, clock: clock, hearing: hearing, mute: mute, published: published)
        hearing.isHeard = false
        await startsAgain(player, arbiter, clock: clock)
        #expect(await player.pauseCallCount == 1)
        #expect(mute.muteCount == 0)
        #expect(published.state == .pausedByMonitor)
    }

    @Test("a player that keeps starting again by itself and can't be muted plays on, its pause failed")
    func selfRestartUnmutable() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, mute: FakeMute(works: false), published: published)
        for _ in 0...PlaybackArbiter.maxRepauses { await startsAgain(player, arbiter, clock: clock) }
        #expect(await player.pauseCallCount == 1 + PlaybackArbiter.maxRepauses)
        #expect(published.state == .pauseFailed)
    }

    @Test("a mute in place of the pause is lifted as the monitoring stops, never left on")
    func muteLiftedAtShutdown() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, mute: mute, published: published)
        for _ in 0...PlaybackArbiter.maxRepauses { await startsAgain(player, arbiter, clock: clock) }
        #expect(mute.muteCount == 1)
        await arbiter.shutdown()
        #expect(mute.unmuteCount == 1)
    }

    @Test("with Resume playback off, a player muted in place of the pause is paused for real, then unmuted, as the apps stop")
    func mutedKeptPausedWithoutResume() async {
        var configuration = AppConfiguration.testing
        configuration.resumesPlayback = false
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, mute: mute, published: published, configuration: configuration)
        for _ in 0...PlaybackArbiter.maxRepauses { await startsAgain(player, arbiter, clock: clock) }
        #expect(mute.muteCount == 1)
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { mute.unmuteCount == 1 }
        #expect(await player.pauseCallCount == 2 + PlaybackArbiter.maxRepauses) // and once more for real
        #expect(await player.state == .paused)
    }

    @Test("a mute made as the monitoring stops is lifted at once")
    func muteDuringShutdownLifted() async {
        let player = MockMusicPlayer(), clock = ManualClock(), mute = FakeMute(), published = LastPublished()
        let arbiter = await pausedForVLC(player, clock: clock, mute: mute, published: published)
        mute.whileMuting = { await arbiter.shutdown() }
        for _ in 0...PlaybackArbiter.maxRepauses { await startsAgain(player, arbiter, clock: clock) }
        #expect(mute.muteCount == 1)
        #expect(mute.unmuteCount == 1)
    }

    @Test("each pause or play AutoHush makes itself is told, so a polled player's next read is reported: its pause, a pause again, the resume")
    func ownCommandsTold() async {
        let player = MockMusicPlayer(), clock = ManualClock(), published = LastPublished()
        let commanded = Locked(0)
        let arbiter = await pausedForVLC(player, clock: clock, published: published, commanded: commanded)
        #expect(commanded.value == 1) // the pause
        await startsAgain(player, arbiter, clock: clock)
        #expect(commanded.value == 2) // paused again
        await arbiter.sourceChanged("org.videolan.vlc", playing: false)
        await TestWait.until { await player.playCallCount == 1 }
        await TestWait.until { commanded.value == 3 } // the resume
        #expect(commanded.value == 3)
    }
}
