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
package actor BackedUpPlayer<Inner: MusicPlayer>: MusicPlayer, TapsAllowingPlayer, BackupRouting, ControlsReporting {
    package nonisolated let inner: Inner
    /// Its backups' players, in their order (the Play/Pause key, then the panel, last).
    nonisolated let backups: [CheckedPlayer.Backup]
    /// How its own way did, and each backup (`nil` where untested).
    private nonisolated let ownResult: CheckResult.WayResult
    private nonisolated let backupResults: [CheckResult.WayResult?]
    nonisolated let lastUsed = OSAllocatedUnfairLock(initialState: LastControls())
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
    /// Only its own player and its backups tell its state.
    nonisolated var statesWithoutOwnWay: Bool { false }
    var ownWayDenied: MusicPlayerError? {
        didSet {
            let denied = ownWayDenied != nil
            ownWayDeniedNow.withLock { $0 = denied }
        }
    }
    /// The same, read where its actor can't be waited for (`makeStateObserver`).
    private nonisolated let ownWayDeniedNow = OSAllocatedUnfairLock(initialState: false)
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
        ownResult = own
        backupResults = results
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
    /// Its own player's; while its own way's permission is missing, a
    /// polled state's (`makeStateObserver`).
    package nonisolated var stateReportDelay: TimeInterval {
        ownWayDeniedNow.withLock { $0 } ? max(inner.stateReportDelay, PolledStateObserver.reportDelay) : inner.stateReportDelay
    }
    /// With its backups in use it checks each way's press itself, as an
    /// added app does (`press(_:to:checkable:)`).
    package nonisolated var checksItsPresses: Bool { routes || inner.checksItsPresses }
    package nonisolated var releasesOnQuit: Bool { inner.releasesOnQuit || learningPage != nil }

    /// Its own player's; with its backups on, its page's switch turned on
    /// too, so its page is built wherever its window goes. Its own player's
    /// permission missing, its backups control it if one can be pressed
    /// without macOS asking (`passesOverOwnWay`).
    package func verifyControlAccess() async throws {
        try await verifyAccess(usesBackups: usesBackups) { try await inner.verifyControlAccess() }
        if routes { await learningPage?.showPage() }
    }
    package func playerState() async -> PlayerState { await stateNow() }

    /// Its own player's state; while its own way's permission is missing
    /// (`ownWayDenied`), which leaves it unknown (its script can't be asked),
    /// the first backup that tells it: its menu's item, its page's word, a
    /// backup script; never the Play/Pause key, which tells nothing, nor the
    /// panel, which shows on screen to be read (the user, 2026-11-05).
    func stateNow() async -> PlayerState {
        // Its own way can't be asked (each ask would fail, logged).
        guard ownWayDenied != nil else { return await inner.playerState() }
        for backup in backups where [.menu, .page, .script].contains(backup.kind) {
            let state = await backup.player.playerState()
            if state != .unknown { return state }
        }
        return .unknown
    }
    package func statesItself() async -> Bool { await inner.statesItself() }
    package func volume() async -> Int? { await inner.volume() }
    package func setVolume(_ volume: Int) async throws { try await inner.setVolume(volume) }
    package func needsReopen() async -> Bool { await inner.needsReopen() }
    package func reopen() async -> Bool { await inner.reopen() }

    /// Its own player's; while its own way's permission is missing, read
    /// about once a second from its backups (`stateNow`): its own player
    /// announces nothing it can be asked about then.
    /// Both run, so a permission taken away or given back while AutoHush
    /// runs is followed without a new session: its own player's reports
    /// (unknown, ignored, while it can't be asked) and, with backups, its
    /// backups' state read once a second only while that lasts.
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        let own = inner.makeStateObserver(onChange: onChange)
        guard wayOrder != nil else { return own }
        return BothStateObservers(own, PolledStateObserver(read: { [self] in await self.stateWhileDenied() }, onChange: onChange))
    }

    /// Its backups' state while its own way's permission is missing; else
    /// unknown, which says nothing.
    private func stateWhileDenied() async -> PlayerState {
        ownWayDenied == nil ? .unknown : await stateNow()
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

    /// With its backups on, or another main control chosen in Settings
    /// (pressed alone while they're off), by the routing; else by its own player.
    package func pause() async throws {
        guard routes else { return try await own(.paused) { try await inner.pause() } }
        try await pause(covered: true)
    }

    package func pauseUncovered() async throws {
        guard routes else { return try await own(.paused) { try await inner.pauseUncovered() } }
        try await pause(covered: false)
    }

    /// Its main control's place in `wayOrder`: another than its own when the
    /// user chose one in Settings (the user, 2026-11-05); never its page
    /// before its button is learned, which it learns only from a pause by
    /// another way (Spotify's).
    nonisolated var mainIndex: Int {
        guard let wayOrder else { return 0 }
        let index = wayOrder.mainIndex(for: switches().mainControl)
        return wayOrder.ways[index].kind == .page && !pageLearned ? 0 : index
    }

    /// Its page way's button is learned (or it has no page to learn).
    private nonisolated var pageLearned: Bool { learningPage?.learningStatus.isLearned != false }

    /// Pressed by the routing: its backups on, or another main control chosen.
    private nonisolated var routes: Bool { usesBackups || mainIndex != 0 }

    /// A press by its own player alone (its backups off), noted as its own.
    private func own(_ target: PlayerState, _ press: () async throws -> Void) async throws {
        ownPressBegins()
        try await press()
        let kind = WayOrder.Kind(ownResult.kind)
        lastUsed.withLock { $0.note(kind, for: target) }
    }

    private func pause(covered: Bool) async throws {
        let noted = await notePlayingForPage()
        try await pressByBackups(to: .paused, covered: covered, alone: !usesBackups)
        if noted { _ = await learningPage?.markPaused() }
    }

    package func play() async throws {
        guard routes else { return try await own(.playing) { try await inner.play() } }
        await learningPage?.showPage()
        try await pressByBackups(to: .playing, alone: !usesBackups)
    }

    package func pauseQuietly() async throws {
        guard routes else { return try await own(.paused) { try await inner.pauseQuietly() } }
        try await pauseWhileMuted(alone: !usesBackups)
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

    // MARK: - What controls it

    /// Its own way, its backups (the Play/Pause key untested), their
    /// switches, and which paused and played it last.
    package nonisolated var controls: PlayerControls {
        let all = [PlayerControls.Control(kind: WayOrder.Kind(ownResult.kind), result: ownResult)]
            + zip(backups, backupResults).map { PlayerControls.Control(kind: $0.kind, result: $1) }
        let main = mainIndex
        let learned = pageLearned
        return PlayerControls(all: all, chosen: main == 0 ? nil : wayOrder?.ways[main].kind,
                              choosable: { CheckedPlayer.choosable($0, at: $1) && (learned || $0.kind != .page) },
                              switches: switches(),
                              notLearned: (inner as? any LearningMusicPlayer)?.learningStatus.isLearned == false,
                              last: lastUsed.withLock { $0 },
                              // Its page, before it's learned: listed dimmed, choosable once learned.
                              notYet: { !learned && $0.kind == .page && CheckedPlayer.choosable($0, at: $1) })
    }

    // MARK: - BackupRouting

    func way(at index: Int) -> any MusicPlayer { index == 0 ? inner : backups[index - 1].player }

    var panelWhileMuted: Bool { switches().panelWhileMuted }

    func sureState() async -> PlayerState { await stateNow() }

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
                             state: { [self] in await self.stateNow() }, sleep: pressSleep).press(to: target)
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

/// Two state observers started and stopped together.
@MainActor
private final class BothStateObservers: PlayerStateObserving {
    private let first: any PlayerStateObserving
    private let second: any PlayerStateObserving

    init(_ first: any PlayerStateObserving, _ second: any PlayerStateObserving) {
        self.first = first
        self.second = second
    }

    func start() {
        first.start()
        second.start()
    }

    func stop() {
        first.stop()
        second.stop()
    }
}
