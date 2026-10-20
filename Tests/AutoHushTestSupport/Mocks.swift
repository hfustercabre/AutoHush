import AppKit
import Foundation
import os
import Testing
import AutoHushKit

// MARK: - MockMusicPlayer

package actor MockMusicPlayer: MusicPlayer {
    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated let volumeCurve: VolumeCurve
    package nonisolated let canFade: Bool
    package nonisolated let iconPlaceholder: PlayerIconPlaceholder?
    package nonisolated let stateReportDelay: TimeInterval
    package nonisolated let kind: MusicPlayerKind
    package nonisolated let releasesOnQuit: Bool
    package nonisolated let checksItsPresses: Bool
    /// The changes its observer reports: a test plays or pauses it as the
    /// user would (`userSets`).
    package nonisolated let stateReports = StateReports()
    package var state: PlayerState
    package var pauseCallCount = 0
    package var playCallCount = 0
    package var verifyCallCount = 0
    package var stateQueryCount = 0
    package var failPauseWith: any Error?
    package var failPlayWith: any Error?
    package var failVerifyWith: any Error?
    /// The next this many state queries answer `.unknown`, as when the player
    /// is busy and doesn't answer in time.
    package var unansweredStateQueries = 0
    /// Runs inside every state query before it answers, so a test can hold a
    /// query while it changes something.
    package var beforeStateAnswer: (@Sendable () async -> Void)?
    /// Runs inside every access check before it answers, so a test can hold
    /// a start there while it changes something.
    package var beforeVerify: (@Sendable () async -> Void)?

    package init(
        bundleID: String = "com.example.jukebox",
        name: String = "Jukebox",
        state: PlayerState = .playing,
        volumeCurve: VolumeCurve = .linear,
        canFade: Bool = true,
        iconPlaceholder: PlayerIconPlaceholder? = nil,
        stateReportDelay: TimeInterval = 0,
        kind: MusicPlayerKind = .app,
        releasesOnQuit: Bool = false,
        checksItsPresses: Bool = false,
        needsReopening: Bool = false,
        failPauseWith: any Error? = nil,
        failPlayWith: any Error? = nil,
        failVerifyWith: any Error? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.state = state
        self.volumeCurve = volumeCurve
        self.canFade = canFade
        self.iconPlaceholder = iconPlaceholder
        self.stateReportDelay = stateReportDelay
        self.kind = kind
        self.releasesOnQuit = releasesOnQuit
        self.checksItsPresses = checksItsPresses
        self.needsReopening = needsReopening
        self.failPauseWith = failPauseWith
        self.failPlayWith = failPlayWith
        self.failVerifyWith = failVerifyWith
    }

    package func verifyControlAccess() async throws {
        verifyCallCount += 1
        if let beforeVerify { await beforeVerify() }
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
    package func setFailPlay(_ error: any Error?) { failPlayWith = error }
    package func setFailPause(_ error: any Error?) { failPauseWith = error }
    package func setFailVerify(_ error: any Error?) { failVerifyWith = error }

    package func setBeforeStateAnswer(_ hook: (@Sendable () async -> Void)?) { beforeStateAnswer = hook }
    package func setBeforeVerify(_ hook: (@Sendable () async -> Void)?) { beforeVerify = hook }

    /// The player's volume; `nil` (the default) means it has none, so no fades.
    package var volumeLevel: Int?
    /// Every volume set, in order.
    package var volumeHistory: [Int] = []
    /// Pauses, plays and volume changes, in order.
    package var commandLog: [String] = []

    package func setVolumeLevel(_ level: Int?) { volumeLevel = level }

    /// Runs inside every volume read before it answers, so a test can hold a
    /// read while it changes something.
    package var beforeVolumeAnswer: (@Sendable () async -> Void)?

    package func setBeforeVolumeAnswer(_ hook: (@Sendable () async -> Void)?) { beforeVolumeAnswer = hook }

    package func volume() async -> Int? {
        if let beforeVolumeAnswer { await beforeVolumeAnswer() }
        return volumeLevel
    }

    package func setVolume(_ volume: Int) async throws {
        volumeLevel = volume
        volumeHistory.append(volume)
        commandLog.append("volume \(volume)")
    }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        stateReports.onChange = onChange
        return MockStateObserver()
    }

    /// Lets tests override the reported state without going through pause/play.
    package func overrideState(_ newState: PlayerState) { state = newState }

    /// The user plays or pauses it: its state changes, and its observer
    /// reports it.
    @MainActor
    package func userSets(_ newState: PlayerState) async {
        await overrideState(newState)
        stateReports.onChange?(newState)
    }

    /// How many presses (pauses or plays) to ignore, as a player that
    /// doesn't follow one: the call succeeds, but its state stays.
    package var ignoredPresses = 0
    package func setIgnoredPresses(_ count: Int) { ignoredPresses = count }

    package func pause() async throws {
        pauseCallCount += 1
        commandLog.append("pause")
        if let error = failPauseWith { throw error }
        guard ignoredPresses == 0 else { ignoredPresses -= 1; return }
        state = .paused
    }

    package func play() async throws {
        playCallCount += 1
        commandLog.append("play")
        if let error = failPlayWith { throw error }
        guard ignoredPresses == 0 else { ignoredPresses -= 1; return }
        state = .playing
    }

    /// It can be heard while it says it's paused (a web app's ad), for
    /// `MockMutingMusicPlayer`: asked to, it mutes itself, and counts as paused.
    package var playsAnyway = false
    package var muteIfPlayingAnywayCount = 0

    package func setPlaysAnyway(_ value: Bool) { playsAnyway = value }

    package func muteIfPlayingAnyway() -> Bool {
        muteIfPlayingAnywayCount += 1
        guard playsAnyway else { return false }
        commandLog.append("mute")
        state = .paused
        return true
    }

    package func forgetPause() { commandLog.append("forgetPause") }

    /// It runs without what it needs (`needsReopen`) until reopened, which
    /// fixes that unless `reopenKeepsNeed` (a launcher that drops the option).
    package var needsReopening = false
    package var reopenKeepsNeed = false
    package var reopenCount = 0

    package func setNeedsReopening(_ needs: Bool, afterReopen: Bool = false) {
        needsReopening = needs
        reopenKeepsNeed = afterReopen
    }

    package func needsReopen() -> Bool { needsReopening }

    package func reopen() -> Bool {
        reopenCount += 1
        needsReopening = reopenKeepsNeed
        return true
    }

    /// How many times it let go of what it turned on in its app.
    package private(set) var releases = 0
    /// Held, a release waits for `letGo()`.
    private var heldReleases: [CheckedContinuation<Void, Never>]?

    package func holdReleases() { heldReleases = heldReleases ?? [] }

    package func letGo() {
        heldReleases?.forEach { $0.resume() }
        heldReleases = nil
    }

    package func release() async {
        if heldReleases != nil { await withCheckedContinuation { heldReleases?.append($0) } }
        releases += 1
    }
}

/// What a `MockMusicPlayer`'s observer reports to, once made.
@MainActor
package final class StateReports {
    var onChange: (@MainActor (PlayerState) -> Void)?
    nonisolated init() {}
}

// MARK: - MockMutingMusicPlayer

/// A `MockMusicPlayer` that taps its own sound, as a web app does: it mutes
/// itself through a tap, which `allowTaps` turns off.
package actor MockMutingMusicPlayer: MutingMusicPlayer {
    package let mock: MockMusicPlayer
    private let tapsAllowed = OSAllocatedUnfairLock(initialState: true)

    package init(_ mock: MockMusicPlayer) {
        self.mock = mock
    }

    package nonisolated var bundleID: String { mock.bundleID }
    package nonisolated var name: String { mock.name }
    package nonisolated var stateReportDelay: TimeInterval { mock.stateReportDelay }
    package nonisolated var tapsAreAllowed: Bool { tapsAllowed.withLock { $0 } }

    package nonisolated func allowTaps(_ allowed: Bool) { tapsAllowed.withLock { $0 = allowed } }

    /// Runs inside every check before muting, so a test can hold one there
    /// while it changes something.
    private var beforeMute: (@Sendable () async -> Void)?
    package func setBeforeMute(_ hook: (@Sendable () async -> Void)?) { beforeMute = hook }

    package func muteIfPlayingAnyway() async -> Bool {
        if let beforeMute { await beforeMute() }
        return await mock.muteIfPlayingAnyway()
    }
    package func forgetPause() async { await mock.forgetPause() }
    package func verifyControlAccess() async throws { try await mock.verifyControlAccess() }
    package func playerState() async -> PlayerState { await mock.playerState() }
    package func pause() async throws { try await mock.pause() }
    package func play() async throws { try await mock.play() }
    package func volume() async -> Int? { await mock.volume() }
    package func setVolume(_ volume: Int) async throws { try await mock.setVolume(volume) }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        MockStateObserver()
    }
}

// MARK: - ManualDebounceScheduler

package final class ManualDebounceScheduler: PlaybackArbiterDebounceScheduling, @unchecked Sendable {
    package init() {}
    private var pendingTasks: [Task<Void, Never>] = []
    private var recordedDelays: [TimeInterval] = []
    private let lock = NSLock()
    /// Never stepped: a debounce's task sleeps until it's cancelled.
    private let held = ManualSleep()

    /// A task that ends once it's cancelled (by the arbiter, or
    /// `completeNext`). Until then it waits without running, so one the
    /// arbiter drops uncancelled costs nothing for the rest of the run.
    package func scheduleDebounce(after delay: TimeInterval) -> Task<Void, Never> {
        lock.withLock {
            recordedDelays.append(delay)
            let task = Task<Void, Never> { [held] in await held.sleep(.seconds(delay)) }
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

/// Keeps preferences in memory, so tests never write preference files. Each
/// value is kept as UserDefaults keeps it, as a property list: one that
/// isn't (a Set, a struct, which UserDefaults can't store) is an issue, and
/// what's read back is the Foundation form UserDefaults hands back.
package final class InMemoryPreferenceStore: PreferenceStore {
    package init() {}
    private var values: [String: Any] = [:]

    package func object(forKey key: String) -> Any? { values[key] }

    package func set(_ value: Any?, forKey key: String) {
        guard let value else {
            values[key] = nil
            return
        }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
            values[key] = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            Issue.record("\(key) isn't a property list, which UserDefaults can't store: \(value)")
            values[key] = value
        }
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
