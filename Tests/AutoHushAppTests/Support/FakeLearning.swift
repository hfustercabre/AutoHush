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
    nonisolated let installedURL: URL?
    nonisolated let isUntested: Bool
    nonisolated var kind: MusicPlayerKind { .safariWebApp }
    nonisolated var controlPermission: Permission { .accessibility(player: name) }
    nonisolated var canFade: Bool { false }

    private struct State {
        var status: LearningStatus
        var listeners: [AsyncStream<LearningStatus>.Continuation] = []
        var learnAgainCount = 0
        var restartCount = 0
        /// What It's Playing and It's Paused answer; `.noted` moves it on.
        var playingMark = LearningMark.noted
        var pausedMark = LearningMark.noted
    }

    private nonisolated let state: OSAllocatedUnfairLock<State>

    init(bundleID: String, name: String, status: LearningStatus, installedURL: URL? = nil, isUntested: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.installedURL = installedURL
        self.isUntested = isUntested
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

    /// How many times it was asked to learn again.
    nonisolated var learnAgainCount: Int { state.withLock { $0.learnAgainCount } }

    func learnAgain() async {
        state.withLock { $0.learnAgainCount += 1 }
        set(.learning(hasPlayed: false))
    }

    /// What It's Playing and It's Paused answer from now on.
    nonisolated func answer(playing: LearningMark = .noted, paused: LearningMark = .noted) {
        state.withLock {
            $0.playingMark = playing
            $0.pausedMark = paused
        }
    }

    /// How many times learning started over (the pause didn't come in time).
    nonisolated var restartCount: Int { state.withLock { $0.restartCount } }

    func markPlaying() async -> LearningMark {
        let mark = state.withLock { $0.playingMark }
        if mark == .noted { set(.learning(hasPlayed: true)) }
        return mark
    }

    func markPaused() async -> LearningMark {
        let mark = state.withLock { $0.pausedMark }
        if mark == .noted { set(.learned) }
        if mark == .tooLate || mark == .cantSeePage { set(.learning(hasPlayed: false)) }
        return mark
    }

    func restartLearning() async {
        state.withLock { $0.restartCount += 1 }
        set(.learning(hasPlayed: false))
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

/// Stands in for the "Add a Web App" window.
@MainActor
final class FakeAddWebAppWindow: AddWebAppPresenting {
    private(set) var isVisible = false
    func show() { isVisible = true }
    func close() { isVisible = false }
}

/// Makes a web app in memory: reports the steps, then `onMake` puts it in place.
final class FakeWebAppMaker: WebAppMaking, @unchecked Sendable {
    var result: Result<MadeWebApp, WebAppMakingError>
    var onMake: @Sendable () -> Void = {}
    /// Once the address is checked, waits until it's cancelled.
    var waitsForCancel = false
    private(set) var wasCancelled = false

    init(_ result: Result<MadeWebApp, WebAppMakingError>) {
        self.result = result
    }

    func makeWebApp(from address: String, onStep: @escaping @Sendable (WebAppMakingStep) -> Void,
                    confirmAdd: @escaping @Sendable () async -> Bool) async throws -> MadeWebApp {
        let made = try result.get()
        onStep(.checked)
        if waitsForCancel {
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
            wasCancelled = true
            throw CancellationError()
        }
        onStep(.opened)
        if !made.alreadyThere {
            onStep(.readyToAdd(site: address))
            guard await confirmAdd() else { throw CancellationError() }
            onStep(.adding)
            onMake()
        }
        onStep(.made(made))
        return made
    }
}
