import Foundation
import AutoHushKit

/// A `MockMusicPlayer` that taps its own sound, as a web app does: it mutes
/// itself through a tap, which `allowTaps` turns off.
package actor MockMutingMusicPlayer: MutingMusicPlayer {
    package let mock: MockMusicPlayer
    private let tapsAllowed = Locked(true)

    package init(_ mock: MockMusicPlayer) {
        self.mock = mock
    }

    package nonisolated var bundleID: String { mock.bundleID }
    package nonisolated var name: String { mock.name }
    package nonisolated var stateReportDelay: TimeInterval { mock.stateReportDelay }
    package nonisolated var tapsAreAllowed: Bool { tapsAllowed.value }

    package nonisolated func allowTaps(_ allowed: Bool) { tapsAllowed.value = allowed }

    /// Runs inside every check before muting, so a test can hold one there
    /// while it changes something.
    private var beforeMute: (@Sendable () async -> Void)?
    package func setBeforeMute(_ hook: (@Sendable () async -> Void)?) { beforeMute = hook }

    package func muteIfPlayingAnyway() async -> Bool {
        if let beforeMute { await beforeMute() }
        return await mock.muteIfPlayingAnyway()
    }
    package func forgetPause() async { await mock.forgetPause() }
    /// Whether its pause is a mute of its own now (`isMutedForPause`).
    package var mutedForPause = false
    package func setMutedForPause(_ muted: Bool) { mutedForPause = muted }
    package func isMutedForPause() async -> Bool { mutedForPause }
    /// How many times a mute was lifted for good (`releaseMute`).
    package private(set) var releasedMutes = 0
    package func releaseMute() async { releasedMutes += 1 }
    package func verifyControlAccess() async throws { try await mock.verifyControlAccess() }
    package func playerState() async -> PlayerState { await mock.playerState() }
    package func pause() async throws { try await mock.pause() }
    package func play() async throws { try await mock.play() }
    package func volume() async -> Int? { await mock.volume() }
    package func setVolume(_ volume: Int) async throws { try await mock.setVolume(volume) }

    /// Its inner mock's observer, so `userSets` on the mock reaches it too.
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        mock.makeStateObserver(onChange: onChange)
    }
}
