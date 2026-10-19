import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlaybackArbiter", .timeLimit(.minutes(1)))
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
            onPlaybackStateChange: { state in stream.yield(state) }
        )
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
            onPlaybackStateChange: onPlaybackStateChange, onAudioLevelsNeededChange: onAudioLevelsNeededChange
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

extension PlaybackArbiter {
    /// Reports a source change, then waits for the pause it may start, so a
    /// test sees its outcome.
    func sourceChanged(_ sourceID: String, playing: Bool, heardSince: Date? = nil) async {
        await handleSourceChange(sourceID: sourceID, isPlaying: playing, heardSince: heardSince)
        await waitForPause()
    }
}

/// Records what the arbiter asks of the volume leveler. As the real one,
/// it lowers once until put back, and a put-back with another lowering's
/// token does nothing (it isn't logged).
final class RecordingVolumeLeveler: ResumeLeveling, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    private var lowered: UUID?
    var log: [String] { lock.withLock { _log } }

    func lower(by decibels: Float) -> UUID? {
        lock.withLock {
            _log.append("lower \(decibels)")
            guard lowered == nil else { return nil }
            lowered = UUID()
            return lowered
        }
    }

    func restore(over duration: TimeInterval, lowered token: UUID) {
        putBack(token, as: "restore over \(duration)")
    }

    func restoreNow(lowered token: UUID) {
        putBack(token, as: "restore now")
    }

    func restoreNow() {
        lock.withLock {
            _log.append("restore now (any)")
            lowered = nil
        }
    }

    private func putBack(_ token: UUID, as entry: String) {
        lock.withLock {
            guard token == lowered else { return }
            _log.append(entry)
            lowered = nil
        }
    }
}

/// Counts a fade's steps (each sleep before a volume change) and holds it
/// at the ones given until let go, so a test acts mid-fade, however busy the
/// machine.
actor FadeSteps {
    private(set) var count = 0
    private var holds: [Int: Gate] = [:]

    init(holdingAt steps: Int...) {
        for step in steps { holds[step] = Gate() }
    }

    func step() async {
        count += 1
        await holds[count]?.wait()
    }

    func letGo(_ step: Int) async { await holds[step]?.open() }
}
