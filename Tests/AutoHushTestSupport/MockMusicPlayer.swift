import AppKit
import Foundation
import Testing
import AutoHushKit

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
    /// Its pause is a mute (an app added as Mute It Instead).
    package nonisolated let pausesByMuting: Bool
    /// The changes its observer reports: a test plays or pauses it as the
    /// user would (`userSets`).
    package nonisolated let stateReports = StateReports()
    package var state: PlayerState {
        didSet { plays.value = state == .playing }
    }
    /// Whether it plays now, readable from any thread: a stand-in for its
    /// sound follows it (`MockLevelMeter.follow`).
    package nonisolated let plays: Locked<Bool>
    package var pauseCallCount = 0
    package var playCallCount = 0
    package var verifyCallCount = 0
    package var stateQueryCount = 0
    package var failPauseWith: any Error?
    package var failPlayWith: any Error?
    package var failVerifyWith: any Error?
    /// Whether its state comes from the player itself (`statesItself`); one
    /// known only by its open output doesn't.
    package var statesItsOwnState = true
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
        bundleID: String = TestPlayer.bundleID,
        name: String = "Jukebox",
        state: PlayerState = .playing,
        volumeCurve: VolumeCurve = .linear,
        canFade: Bool = true,
        iconPlaceholder: PlayerIconPlaceholder? = nil,
        stateReportDelay: TimeInterval = 0,
        kind: MusicPlayerKind = .app,
        releasesOnQuit: Bool = false,
        checksItsPresses: Bool = false,
        pausesByMuting: Bool = false,
        needsReopening: Bool = false,
        failPauseWith: any Error? = nil,
        failPlayWith: any Error? = nil,
        failVerifyWith: any Error? = nil
    ) {
        self.bundleID = bundleID
        self.name = name
        self.state = state
        plays = Locked(state == .playing)
        self.volumeCurve = volumeCurve
        self.canFade = canFade
        self.iconPlaceholder = iconPlaceholder
        self.stateReportDelay = stateReportDelay
        self.kind = kind
        self.releasesOnQuit = releasesOnQuit
        self.pausesByMuting = pausesByMuting
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

    package func statesItself() async -> Bool { statesItsOwnState }
    package func setStatesItself(_ states: Bool) { statesItsOwnState = states }
    package func setFailPlay(_ error: any Error?) { failPlayWith = error }
    package func setFailPause(_ error: any Error?) { failPauseWith = error }
    package func setFailVerify(_ error: any Error?) { failVerifyWith = error }

    package func setBeforeStateAnswer(_ hook: (@Sendable () async -> Void)?) { beforeStateAnswer = hook }
    /// Runs inside every play, after it's counted and before it answers.
    package var beforePlay: (@Sendable () async -> Void)?
    package func setBeforePlay(_ hook: (@Sendable () async -> Void)?) { beforePlay = hook }
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
    /// Changes by itself, unannounced (the user, or the app).
    package func setState(_ state: PlayerState) { self.state = state }

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
        if let beforePlay { await beforePlay() }
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
    /// A reopen that doesn't go (it didn't quit, or didn't open again).
    package var reopenFails = false

    package func setReopenFails(_ fails: Bool) { reopenFails = fails }

    package func setNeedsReopening(_ needs: Bool, afterReopen: Bool = false) {
        needsReopening = needs
        reopenKeepsNeed = afterReopen
    }

    package func needsReopen() -> Bool { needsReopening }

    package func reopen() -> Bool {
        reopenCount += 1
        if reopenFails { return false }
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
