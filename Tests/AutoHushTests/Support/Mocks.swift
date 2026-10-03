import AppKit
import Foundation
import Testing
@testable import AutoHush

// MARK: - MockMusicPlayer

actor MockMusicPlayer: MusicPlayer {
    nonisolated var bundleID: String { "com.example.player" }
    nonisolated var name: String { "Spotify" }
    var state: PlayerState
    var pauseCallCount = 0
    var playCallCount = 0
    var verifyCallCount = 0
    var stateQueryCount = 0
    var failPauseWith: Error?
    var failPlayWith: Error?
    var failVerifyWith: Error?
    /// The next this many state queries answer `.unknown`, as when Spotify is
    /// busy and the Apple event times out.
    var unansweredStateQueries = 0

    init(
        state: PlayerState = .playing,
        failPauseWith: Error? = nil,
        failPlayWith: Error? = nil,
        failVerifyWith: Error? = nil
    ) {
        self.state = state
        self.failPauseWith = failPauseWith
        self.failPlayWith = failPlayWith
        self.failVerifyWith = failVerifyWith
    }

    func verifyControlAccess() async throws {
        verifyCallCount += 1
        if let error = failVerifyWith { throw error }
    }

    func playerState() async -> PlayerState {
        stateQueryCount += 1
        if unansweredStateQueries > 0 {
            unansweredStateQueries -= 1
            return .unknown
        }
        return state
    }

    func setUnansweredStateQueries(_ count: Int) { unansweredStateQueries = count }

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }

    /// Lets tests override the reported state without going through pause/play.
    func overrideState(_ newState: PlayerState) { state = newState }

    func pause() async throws {
        pauseCallCount += 1
        if let error = failPauseWith { throw error }
        state = .paused
    }

    func play() async throws {
        playCallCount += 1
        if let error = failPlayWith { throw error }
        state = .playing
    }
}

// MARK: - MockLaunchAtLoginController

@MainActor
final class MockLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    var setEnabledCalls: [Bool] = []
    /// Override per-test to control what `setEnabled(_:)` returns.
    /// Defaults to `.success(())` so tests that don't set it get a passing result.
    var setEnabledResult: Result<Void, Error> = .success(())
    var openSystemSettingsCallCount = 0

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        setEnabledCalls.append(enabled)
        switch setEnabledResult {
        case .success:
            isEnabled = enabled
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    func openSystemSettings() {
        openSystemSettingsCallCount += 1
    }
}

// MARK: - ManualDebounceScheduler

final class ManualDebounceScheduler: PlaybackArbiterDebounceScheduling, @unchecked Sendable {
    private var pendingTasks: [Task<Void, Never>] = []
    private var recordedDelays: [TimeInterval] = []
    private let lock = NSLock()

    func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        lock.withLock {
            recordedDelays.append(delay)
            let task = Task<Void, Never> {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(1))
                }
            }
            pendingTasks.append(task)
            return task
        }
    }

    /// Cancels the oldest pending debounce task, letting the resume path proceed.
    func completeNext() async {
        let task: Task<Void, Never>? = lock.withLock {
            pendingTasks.isEmpty ? nil : pendingTasks.removeFirst()
        }
        guard let task else { return }
        task.cancel()
        _ = await task.value
    }

    var scheduledDelays: [TimeInterval] {
        lock.withLock { recordedDelays }
    }
}

// MARK: - StubError

enum StubError: Error, LocalizedError {
    case failed
    var errorDescription: String? { "stub failed" }
}

// MARK: - InMemoryPreferenceStore

/// Keeps preferences in memory, so tests never write preference files.
final class InMemoryPreferenceStore: PreferenceStore {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

// MARK: - MockStateObserver

@MainActor
final class MockStateObserver: PlayerStateObserving {
    private(set) var isObserving = false
    func start() { isObserving = true }
    func stop() { isObserving = false }
}
