import AppKit
import Foundation
import Testing
import AutoHushKit

// MARK: - MockMusicPlayer

package actor MockMusicPlayer: MusicPlayer {
    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated let volumeCurve: VolumeCurve
    package var state: PlayerState
    package var pauseCallCount = 0
    package var playCallCount = 0
    package var verifyCallCount = 0
    package var stateQueryCount = 0
    package var failPauseWith: Error?
    package var failPlayWith: Error?
    package var failVerifyWith: Error?
    /// The next this many state queries answer `.unknown`, as when the player
    /// is busy and doesn't answer in time.
    package var unansweredStateQueries = 0
    /// Runs inside every state query before it answers, so a test can hold a
    /// query while it changes something.
    package var beforeStateAnswer: (@Sendable () async -> Void)?

    package init(
        bundleID: String = "com.example.jukebox",
        name: String = "Jukebox",
        state: PlayerState = .playing,
        volumeCurve: VolumeCurve = .linear,
        failPauseWith: Error? = nil,
        failPlayWith: Error? = nil,
        failVerifyWith: Error? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.state = state
        self.volumeCurve = volumeCurve
        self.failPauseWith = failPauseWith
        self.failPlayWith = failPlayWith
        self.failVerifyWith = failVerifyWith
    }

    package func verifyControlAccess() async throws {
        verifyCallCount += 1
        if let error = failVerifyWith { throw error }
    }

    package func playerState() async -> PlayerState {
        stateQueryCount += 1
        if let beforeStateAnswer { await beforeStateAnswer() }
        if unansweredStateQueries > 0 {
            unansweredStateQueries -= 1
            return .unknown
        }
        return state
    }

    package func setUnansweredStateQueries(_ count: Int) { unansweredStateQueries = count }

    package func setBeforeStateAnswer(_ hook: (@Sendable () async -> Void)?) { beforeStateAnswer = hook }

    /// The player's volume; `nil` (the default) means it has none, so no fades.
    package var volumeLevel: Int?
    /// Every volume set, in order.
    package var volumeHistory: [Int] = []
    /// Pauses, plays and volume changes, in order.
    package var commandLog: [String] = []

    package func setVolumeLevel(_ level: Int?) { volumeLevel = level }

    package func volume() async -> Int? { volumeLevel }

    package func setVolume(_ volume: Int) async throws {
        volumeLevel = volume
        volumeHistory.append(volume)
        commandLog.append("volume \(volume)")
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }

    /// Lets tests override the reported state without going through pause/play.
    package func overrideState(_ newState: PlayerState) { state = newState }

    package func pause() async throws {
        pauseCallCount += 1
        commandLog.append("pause")
        if let error = failPauseWith { throw error }
        state = .paused
    }

    package func play() async throws {
        playCallCount += 1
        commandLog.append("play")
        if let error = failPlayWith { throw error }
        state = .playing
    }
}

// MARK: - ManualDebounceScheduler

package final class ManualDebounceScheduler: PlaybackArbiterDebounceScheduling, @unchecked Sendable {
    package init() {}
    private var pendingTasks: [Task<Void, Never>] = []
    private var recordedDelays: [TimeInterval] = []
    private let lock = NSLock()

    package func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
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
    package func completeNext() async {
        let task: Task<Void, Never>? = lock.withLock {
            pendingTasks.isEmpty ? nil : pendingTasks.removeFirst()
        }
        guard let task else { return }
        task.cancel()
        _ = await task.value
    }

    package var scheduledDelays: [TimeInterval] {
        lock.withLock { recordedDelays }
    }
}

// MARK: - StubError

package enum StubError: Error, LocalizedError {
    case failed
    package var errorDescription: String? { "stub failed" }
}

// MARK: - InMemoryPreferenceStore

/// Keeps preferences in memory, so tests never write preference files.
package final class InMemoryPreferenceStore: PreferenceStore {
    package init() {}
    private var values: [String: Any] = [:]

    package func object(forKey key: String) -> Any? { values[key] }

    package func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }
}

// MARK: - MockStateObserver

@MainActor
package final class MockStateObserver: PlayerStateObserving {
    package init() {}
    private(set) var isObserving = false
    package func start() { isObserving = true }
    package func stop() { isObserving = false }
}

// MARK: - TestPlayer

/// The music player in engine tests. The engine knows no player by name, so
/// tests tell it which app's audio is the music, like the app does.
package enum TestPlayer {
    package static let bundleID = "com.example.jukebox"
}

extension AppConfiguration {
    /// The default configuration, with `TestPlayer` as the chosen player.
    package static var testing: AppConfiguration {
        var configuration = AppConfiguration(timings: .defaults)
        configuration.musicPlayerBundleID = TestPlayer.bundleID
        return configuration
    }
}

// MARK: - TestDates

/// Dates in October 2026 on Madrid time, so tests don't depend on the Mac's
/// time zone.
package enum TestDates {
    package static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }()

    /// The day of October 2026 at the time given, e.g. `date(2, 15, 30)`.
    package static func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
}
