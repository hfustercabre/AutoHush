import Foundation
import os
import AutoHushKit
import AutoHushTestSupport
@testable import AutoHushApp

/// Stands in for the learning window, so tests never put one on screen.
@MainActor
final class FakeLearningWindow: LearningWindowPresenting {
    private(set) var isVisible = false
    private(set) var shownCount = 0
    func show() {
        isVisible = true
        shownCount += 1
    }
    func close() { isVisible = false }
}

/// A player that must learn, whose learning the test moves along; it never
/// can be controlled, so a real bootstrap stops at once.
actor MockLearningPlayer: LearningMusicPlayer {
    nonisolated let bundleID: String
    nonisolated let name: String
    nonisolated var kind: MusicPlayerKind { .safariWebApp }
    nonisolated var controlPermission: Permission { .accessibility(player: name) }
    nonisolated var canFade: Bool { false }

    private struct State {
        var status: LearningStatus
        var listeners: [AsyncStream<LearningStatus>.Continuation] = []
    }

    private nonisolated let state: OSAllocatedUnfairLock<State>

    init(bundleID: String, name: String, status: LearningStatus) {
        self.bundleID = bundleID
        self.name = name
        state = OSAllocatedUnfairLock(initialState: State(status: status))
    }

    nonisolated var learningStatus: LearningStatus { state.withLock { $0.status } }

    nonisolated func learningUpdates() -> AsyncStream<LearningStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: LearningStatus.self)
        let current = state.withLock { state in
            state.listeners.append(continuation)
            return state.status
        }
        continuation.yield(current)
        return stream
    }

    nonisolated func set(_ status: LearningStatus) {
        let listeners = state.withLock { state in
            state.status = status
            return state.listeners
        }
        listeners.forEach { $0.yield(status) }
    }

    func verifyControlAccess() async throws { throw MusicPlayerError.accessibilityPermissionDenied }
    func playerState() async -> PlayerState { .unknown }
    func pause() async throws {}
    func play() async throws {}
    func volume() async -> Int? { nil }
    func setVolume(_ volume: Int) async throws {}

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }
}
