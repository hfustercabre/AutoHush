import AppKit
import Foundation
import os
import AutoHushKit
import MenuPlayers
import ScriptablePlayers
import WebAppPlayers

/// A built-in player or a Safari web app with its backups (the user,
/// 2026-11-05): its own way first, then the ways measured to work for it
/// (`BuiltInBackups`; a web app has none), the Play/Pause key, the Now
/// Playing panel last, pressed by its window's state as an added app's are
/// (`BackupRouting`) while its backups are on (`BackupSwitches`, both on
/// until the user turns one off). Everything else is its own player's
/// (`inner`), which a web app keeps learning and muting through
/// (`LearningMusicPlayer`, `MutingMusicPlayer`). Made once per player, so it
/// stays the same object while it's the player.
package actor BackedUpPlayer<Inner: MusicPlayer>: MusicPlayer, TapsAllowingPlayer, BackupRouting {
    package nonisolated let inner: Inner
    /// Its backups' players, in their order (the Play/Pause key, then the panel, last).
    nonisolated let backups: [CheckedPlayer.Backup]
    let wayOrder: WayOrder?
    /// Its page way, learned as AutoHush pauses it its own way (Spotify's);
    /// `nil` for the others.
    nonisolated let learningPage: SafariWebAppPlayer?
    private nonisolated let switches: @Sendable () -> BackupSwitches
    let processIdentifier: @Sendable () -> pid_t?
    let windowState: @Sendable (pid_t) async -> CheckResult.WindowState
    let backupAllowed: @Sendable (WayOrder.Kind, pid_t) async -> Bool
    let now: @Sendable () -> Date
    let logger = AutoHushLogger(category: "BackedUpPlayer")
    var mutedTried: Set<Int> = []
    var pressCalls = 0
    var panelPlayFailedAt: Date?
    /// Whether it may be muted through a tap: not in AntiDot mode (`allowTaps`).
    private nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    private let audioRecordingAllowed: @Sendable () -> Bool
    private let pressSleep: VolumeFader.Sleep

    /// `own`: how its own way did (worked everywhere for a built-in);
    /// `results`: each backup's, in the same order, `nil` where untested.
    init(inner: Inner, own: CheckResult.WayResult, backups: [CheckedPlayer.Backup], results: [CheckResult.WayResult?],
         learningPage: SafariWebAppPlayer? = nil, keyState: LateState? = nil,
         switches: @escaping @Sendable () -> BackupSwitches,
         processIdentifier: (@Sendable () -> pid_t?)? = nil,
         windowState: @escaping @Sendable (pid_t) async -> CheckResult.WindowState = CheckedPlayer.readWindowState(of:),
         backupAllowed: @escaping @Sendable (WayOrder.Kind, pid_t) async -> Bool = CheckedPlayer.mayPressBackup(_:pid:),
         audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps },
         pressSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.inner = inner
        self.backups = backups
        wayOrder = backups.isEmpty ? nil : WayOrder(ways: [WayOrder.Way(kind: WayOrder.Kind(own.kind), result: own)]
            + zip(backups, results).map { WayOrder.Way(kind: $0.kind, result: $1) })
        self.learningPage = learningPage
        self.switches = switches
        self.processIdentifier = processIdentifier ?? { [bundleID = inner.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.windowState = windowState
        self.backupAllowed = backupAllowed
        self.audioRecordingAllowed = audioRecordingAllowed
        self.pressSleep = pressSleep
        self.now = now
        keyState?.set { [weak self] in await self?.sureState() ?? .unknown }
        // Out of sight, its page's words lag: its own player's state tells.
        learningPage?.otherSigns.set { [weak self] in await self?.sureState() ?? .unknown }
    }

    /// Its backups are pressed: it has some, their switch is on, and it's
    /// learned, a web app (the user, 2026-11-05: until then, as before them).
    private nonisolated var usesBackups: Bool {
        !backups.isEmpty && switches().usesBackups && (inner as? any LearningMusicPlayer)?.learningStatus.isLearned != false
    }

    // MARK: - Its own player's

    package nonisolated var bundleID: String { inner.bundleID }
    package nonisolated var name: String { inner.name }
    package nonisolated var iconPlaceholder: PlayerIconPlaceholder? { inner.iconPlaceholder }
    package nonisolated var controlPermission: Permission { inner.controlPermission }
    package nonisolated var kind: MusicPlayerKind { inner.kind }
    package nonisolated var installedURL: URL? { inner.installedURL }
    package nonisolated var isUntested: Bool { inner.isUntested }
    package nonisolated var ownWordsRead: Bool? { inner.ownWordsRead }
    package nonisolated var volumeCurve: VolumeCurve { inner.volumeCurve }
    package nonisolated var canFade: Bool { inner.canFade }
    package nonisolated var pausesByMuting: Bool { inner.pausesByMuting }
    package nonisolated var needsAudioLevels: Bool { inner.needsAudioLevels }
    package nonisolated var stateReportDelay: TimeInterval { inner.stateReportDelay }
    /// With its backups in use it checks each way's press itself, as an
    /// added app does (`press(_:to:checkable:)`).
    package nonisolated var checksItsPresses: Bool { usesBackups || inner.checksItsPresses }
    package nonisolated var releasesOnQuit: Bool { inner.releasesOnQuit || learningPage != nil }

    /// Its own player's; with its backups on, its page's switch turned on
    /// too, so its page is built wherever its window goes.
    package func verifyControlAccess() async throws {
        try await inner.verifyControlAccess()
        if usesBackups { await learningPage?.showPage() }
    }
    package func playerState() async -> PlayerState { await inner.playerState() }
    package func statesItself() async -> Bool { await inner.statesItself() }
    package func volume() async -> Int? { await inner.volume() }
    package func setVolume(_ volume: Int) async throws { try await inner.setVolume(volume) }
    package func needsReopen() async -> Bool { await inner.needsReopen() }
    package func reopen() async -> Bool { await inner.reopen() }

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        inner.makeStateObserver(onChange: onChange)
    }

    /// Its own player's, and its page's switch turned back off.
    package func release() async {
        await inner.release()
        await learningPage?.releasePage()
    }

    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        (inner as? any TapsAllowingPlayer)?.allowTaps(allowed)
    }

    // MARK: - Pressed with its backups

    package func pause() async throws {
        guard usesBackups else { return try await inner.pause() }
        try await pause(covered: true)
    }

    package func pauseUncovered() async throws {
        guard usesBackups else { return try await inner.pauseUncovered() }
        try await pause(covered: false)
    }

    private func pause(covered: Bool) async throws {
        let noted = await notePlayingForPage()
        try await pressByBackups(to: .paused, covered: covered)
        if noted { _ = await learningPage?.markPaused() }
    }

    package func play() async throws {
        guard usesBackups else { return try await inner.play() }
        await learningPage?.showPage()
        try await pressByBackups(to: .playing)
    }

    package func pauseQuietly() async throws {
        guard usesBackups else { return try await inner.pauseQuietly() }
        try await pauseWhileMuted()
    }

    /// Its page, not learned yet, looked at while it plays, so the pause
    /// teaches it which button changed (`markPaused` after it): about half
    /// a second the first time, its switch turned on for it. Learned, its
    /// switch is kept on (a relaunched app is a new process).
    private func notePlayingForPage() async -> Bool {
        guard let learningPage else { return false }
        guard !learningPage.learningStatus.isLearned else {
            await learningPage.showPage()
            return false
        }
        return await learningPage.markPlaying() == .noted
    }

    // MARK: - BackupRouting

    func way(at index: Int) -> any MusicPlayer { index == 0 ? inner : backups[index - 1].player }

    var panelWhileMuted: Bool { switches().panelWhileMuted }

    func sureState() async -> PlayerState { await inner.playerState() }

    /// As its mute asks (`ProcessPlayerMute`): not in AntiDot mode, with Audio Recording.
    func canBeMuted() async -> Bool {
        guard tapsAllowed.withLock({ $0 }) else { return false }
        let allowed = audioRecordingAllowed
        return await CheckedPlayer.probeQueue.run { allowed() }
    }

    /// One that checks its own presses (a web app's page, the key) as it
    /// is; any other by its own player's state (`PressCheck`).
    func press(_ way: any MusicPlayer, to target: PlayerState, checkable: inout Bool?) async throws {
        if way.checksItsPresses {
            if target == .playing { try await way.play() } else { try await way.pause() }
            return
        }
        try await PressCheck(name: "\(name) (\(type(of: way)))",
                             press: { target in if target == .playing { try await way.play() } else { try await way.pause() } },
                             state: { [inner] in await inner.playerState() }, sleep: pressSleep).press(to: target)
    }
}

// A web app keeps learning and muting through it.
extension BackedUpPlayer: LearningMusicPlayer where Inner: LearningMusicPlayer {
    package nonisolated var learningStatus: LearningStatus { inner.learningStatus }
    package nonisolated func learningUpdates() -> AsyncStream<LearningStatus> { inner.learningUpdates() }
    package func learnAgain() async { await inner.learnAgain() }
    package func keepLearned() async { await inner.keepLearned() }
    package func markPlaying() async -> LearningMark { await inner.markPlaying() }
    package func pauseByItself() async -> SelfPause { await inner.pauseByItself() }
    package func markPaused() async -> LearningMark { await inner.markPaused() }
    @discardableResult
    package func restartLearning() async -> Bool { await inner.restartLearning() }
}

extension BackedUpPlayer: MutingMusicPlayer where Inner: MutingMusicPlayer {
    package func muteIfPlayingAnyway() async -> Bool { await inner.muteIfPlayingAnyway() }
    package func forgetPause() async { await inner.forgetPause() }
    package func releaseMute() async { await inner.releaseMute() }
    package func isMutedForPause() async -> Bool { await inner.isMutedForPause() }
}

extension BackedUpPlayer {
    /// A built-in player with the backups measured for it: each of its
    /// ways, then the Play/Pause key and the panel last.
    package static func builtIn(_ player: Inner, backups measured: BuiltInBackups,
                                switches: BackupSwitchesStore = BackupSwitchesStore()) -> BackedUpPlayer<Inner> {
        let setup = PlayerSetup(bundleID: player.bundleID, name: player.name, appURL: appURL(of: player), ways: [])
        let keyState = LateState()
        var page: SafariWebAppPlayer?
        var ways: [(CheckedPlayer.Backup, CheckResult.WayResult?)] = []
        for backup in measured.backups where backup.way.kind != .panel {
            switch backup.way {
            case .menu(let menuName):
                let menu = MenuPlayer(profile: .found(bundleID: player.bundleID, name: player.name, menuName: menuName))
                ways.append((CheckedPlayer.Backup(player: menu, kind: .menu), backup.result))
            case .page(let access):
                let learning = SafariWebAppPlayer(app: SafariWebApp(bundleID: player.bundleID, name: player.name, url: setup.appURL),
                                                  kind: .app, page: AccessibilityWebPage(access: access), canMute: false,
                                                  mutesRefusals: { false })
                page = learning
                ways.append((CheckedPlayer.Backup(player: learning, kind: .page), backup.result))
            case .panel: break
            }
        }
        ways.append((CheckedPlayer.Backup(player: MediaKeyWay(bundleID: player.bundleID, name: player.name, state: keyState), kind: .mediaKey), nil))
        let panel = measured.backups.first { $0.way.kind == .panel }
        let song: ScriptedSong? = if case .panel(let song)? = panel?.way { song } else { nil }
        var panelSetup = setup
        panelSetup.panelClues = PanelClues(page: nil, script: song)
        ways.append((CheckedPlayer.Backup(player: PanelWay(setup: panelSetup, remembered: nil, store: NoSetups()), kind: .panel), panel?.result))
        let id = player.bundleID
        return BackedUpPlayer(inner: player, own: CheckResult.WayResult(kind: measured.own, mark: .works),
                              backups: ways.map(\.0), results: ways.map(\.1), learningPage: page, keyState: keyState,
                              switches: { switches.switches(for: id) })
    }

    /// A Safari web app: its page, then the Play/Pause key and the panel,
    /// untested by state (the user, 2026-11-05).
    package static func webApp(_ player: Inner, switches: BackupSwitchesStore = BackupSwitchesStore()) -> BackedUpPlayer<Inner> {
        let setup = PlayerSetup(bundleID: player.bundleID, name: player.name, appURL: appURL(of: player), ways: [])
        let keyState = LateState(), id = player.bundleID
        return BackedUpPlayer(inner: player, own: CheckResult.WayResult(kind: .page, mark: .works),
                              backups: [CheckedPlayer.Backup(player: MediaKeyWay(bundleID: id, name: player.name, state: keyState), kind: .mediaKey),
                                        CheckedPlayer.Backup(player: PanelWay(setup: setup, remembered: nil, store: NoSetups()), kind: .panel)],
                              results: [nil, nil], keyState: keyState, switches: { switches.switches(for: id) })
    }
}

/// Where `player` is installed, as far as is known now (the panel and a
/// page way only need its bundle ID and name).
private func appURL(of player: some MusicPlayer) -> URL {
    player.installedURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID)
        ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
}

/// A built-in player keeps no setup: its panel row is remembered while
/// AutoHush runs, never saved (saving one would make it an added app).
private struct NoSetups: PlayerSetupStore {
    func setups() -> [PlayerSetup] { [] }
    func save(_ setup: PlayerSetup) {}
    func forget(_ bundleID: String) {}
    func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {}
}
