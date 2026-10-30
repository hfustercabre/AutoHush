import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlaybackArbiter", .waitsTimeLimit)
struct PlaybackArbiterTests {

    // MARK: - Helpers

    func makeArbiter(
        player: MockMusicPlayer = MockMusicPlayer(),
        configuration: AppConfiguration = .testing,
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler()
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler)
    }

    /// An arbiter for `player`, at volume 60, whose fades take their steps
    /// from `steps`, held where it says.
    func makeFadingArbiter(_ player: MockMusicPlayer, steps: FadeSteps) async -> PlaybackArbiter {
        await player.setVolumeLevel(60)
        return PlaybackArbiter(player: player, configuration: AppConfiguration(), debounceScheduler: ManualDebounceScheduler(),
                               fadeSleep: { _ in await steps.step() })
    }

    /// An arbiter with Level the volume on, lowering the Mac's volume by
    /// 6 dB through `leveler` before each resume.
    func makeLevelingArbiter(
        _ player: MockMusicPlayer, leveler: RecordingVolumeLeveler, scheduler: ManualDebounceScheduler = ManualDebounceScheduler()
    ) -> PlaybackArbiter {
        var configuration = AppConfiguration.testing
        configuration.levelsMusic = true
        return PlaybackArbiter(player: player, configuration: configuration, debounceScheduler: scheduler,
                               fadeSleep: { _ in }, volumeLeveler: leveler, resumeOffset: { -6 })
    }

    /// Delivers PlaybackState values via AsyncStream so tests can await them
    /// without any Task-hop race between the synchronous callback and the assertion.
    final class StateStream: Sendable {
        private let continuation: AsyncStream<PlaybackState>.Continuation
        let stream: AsyncStream<PlaybackState>

        init() {
            (stream, continuation) = AsyncStream.makeStream()
        }

        func yield(_ state: PlaybackState) { continuation.yield(state) }
    }

    func makeArbiterWithStream(
        player: MockMusicPlayer = MockMusicPlayer(),
        stream: StateStream
    ) -> PlaybackArbiter {
        PlaybackArbiter(player: player,
            configuration: AppConfiguration(),
            debounceScheduler: ManualDebounceScheduler(),
            onStatusUpdate: statuses(playback: { state in stream.yield(state) }))
    }

    /// Awaits the next value from the stream, or `nil` after `TestWait.limit`.
    func nextState(from stream: AsyncStream<PlaybackState>) async -> PlaybackState? {
        await withTaskGroup(of: PlaybackState?.self) { group in
            group.addTask {
                for await state in stream { return state }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: TestWait.limit)
                return nil
            }
            let result = await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// The arbiter's status updates, split by kind as the tests follow them.
    func statuses(
        playback: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        pauseFailure: @escaping @Sendable (MusicPlayerError?) -> Void = { _ in },
        resumeFailure: @escaping @Sendable (MusicPlayerError?) -> Void = { _ in },
        mutedInstead: @escaping @Sendable (Bool) -> Void = { _ in }
    ) -> @Sendable (MonitoringStatusUpdate) -> Void {
        { update in
            switch update {
            case .playback(let state): playback(state)
            case .pauseFailure(let failure): pauseFailure(failure)
            case .resumeFailure(let failure): resumeFailure(failure)
            case .mutedInstead(let muted): mutedInstead(muted)
            case .activeSources, .detection, .learnedAssertions: break
            }
        }
    }

    /// An arbiter on the test's clock, knowing its player plays.
    func makeClockedArbiter(
        player: MockMusicPlayer,
        clock: ManualClock,
        configuration: AppConfiguration = .testing,
        scheduler: ManualDebounceScheduler = ManualDebounceScheduler(),
        autoPauseEnabled: Bool = true,
        fadeSleep: @escaping VolumeFader.Sleep = { _ in },
        onPlaybackStateChange: @escaping @Sendable (PlaybackState) -> Void = { _ in },
        onAudioLevelsNeededChange: @escaping @Sendable (Bool) -> Void = { _ in }
    ) async -> PlaybackArbiter {
        let arbiter = PlaybackArbiter(
            player: player, configuration: configuration, debounceScheduler: scheduler, fadeSleep: fadeSleep,
            clock: { clock.now }, autoPauseEnabled: autoPauseEnabled,
            onStatusUpdate: statuses(playback: onPlaybackStateChange), onAudioLevelsNeededChange: onAudioLevelsNeededChange
        )
        await arbiter.refreshPlaybackState()
        return arbiter
    }

    /// Something other than AutoHush pauses the player, and its observer says so.
    func pausedElsewhere(_ player: MockMusicPlayer, _ arbiter: PlaybackArbiter) async {
        await player.overrideState(.paused)
        await arbiter.handlePlayerStateChange(.paused)
    }
}
