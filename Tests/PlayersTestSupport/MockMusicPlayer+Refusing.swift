import AutoHushKit
import AutoHushTestSupport

/// Players whose presses the app ignores, and their pauses counted, for the
/// tests of a player backed up by other ways (one copy: the 2026-11-06 full
/// check's T-12).
extension MockMusicPlayer {
    /// A press the app ignored.
    package static let refused = MusicPlayerError.playerCommandFailed(.pressIgnored)

    /// A player in `state` whose pause (or play, `pause` false) is refused.
    package static func failing(_ state: PlayerState = .playing, pause: Bool = true) async -> MockMusicPlayer {
        let player = MockMusicPlayer(state: state)
        if pause { await player.setFailPause(refused) } else { await player.setFailPlay(refused) }
        return player
    }

    /// How many pauses each of `players` was asked for, in order.
    package static func pauses(_ players: MockMusicPlayer...) async -> [Int] {
        var counts: [Int] = []
        for player in players { counts.append(await player.pauseCallCount) }
        return counts
    }

    /// How many plays each of `players` was asked for, in order.
    package static func plays(_ players: MockMusicPlayer...) async -> [Int] {
        var counts: [Int] = []
        for player in players { counts.append(await player.playCallCount) }
        return counts
    }
}
