import AppKit
import Foundation
import os
import AutoHushKit
import ScriptablePlayers
import WebAppPlayers

/// An app added through a check (`PlayerSetup`), controlled by the way the
/// user chose at Use: its AppleScript, its page's Play/Pause, its playback
/// menu, or its row in the Now Playing panel (the user, 2026-10-15). An
/// older setup may hold several, the surest first, the panel last, tried in
/// that order. Its state is the surest sign that answers: its
/// scripted state, its page's word (while current), its menu's item, what it
/// reported to Now Playing (only where macOS's log can be read, and not once
/// it's found stale), else whether its sound output is on. One whose Now
/// Playing row doesn't follow it (`PlayerSetup.panelRowIsStale`) is told by
/// its level instead, listened to only when AutoHush is about to pause or
/// play it, and read once a second by its keep-awake assertion meanwhile
/// (the user, 2026-10-16: else macOS's recording dot stays on all day).
/// Player Check judges its presses by the same signs in this order, then by
/// the app's level and keep-awake assertion, so what it approves is what
/// AutoHush will do (the user, 2026-10-26).
///
/// It checks its own presses: each by the way that made it, against those
/// signs (`sureState`) and never by its output alone, which stays open for
/// seconds after a pause; a page checks its own, a toggle judged by another
/// sign (a row that doesn't follow it, a script without a state) checks its
/// own without pressing again. One muted instead of paused is a `MutedApp`.
///
/// With its backups on, the other ways that worked are pressed by the
/// window's state (`CheckedPlayer+Backups`, the user, 2026-11-04). Its
/// backup switches are read at each press (`switches`), so Settings changes
/// them without a new player, which would drop a pause AutoHush holds (the
/// user, 2026-11-05).
package actor CheckedPlayer: AddedAppPlayer {
    package nonisolated let setup: PlayerSetup

    /// Through a Now Playing row that doesn't follow it, it needs
    /// Accessibility and Audio Recording: Accessibility is named, since
    /// nothing presses the row without it, and Audio Recording has its own
    /// row and warning, as AutoHush's (and AntiDot mode can't be used with it).
    package nonisolated var controlPermission: Permission {
        if case .script? = setup.ways.first { return .automation(player: name) }
        return .accessibility(player: name)
    }
    package nonisolated var canFade: Bool { parts.volume?.canFade == true }

    nonisolated let parts: Parts
    let reports: NowPlayingReports?
    /// Its running process, if it runs: AutoHush never launches it.
    let processIdentifier: @Sendable () -> pid_t?
    /// What its process was opened with (`needsReopen`).
    let processArguments: @Sendable (pid_t) -> [String]
    /// Opens it with the launch option, in the background (`reopen`).
    let openWithLaunchOption: @Sendable (URL) async -> Bool
    /// Whether its sound output is on (a process of its own plays).
    let soundOn: @Sendable (pid_t) -> Bool
    let levelProbe: any AudioLevelProbing
    private let pressSleep: VolumeFader.Sleep
    let logger = AutoHushLogger(category: "CheckedPlayer")
    /// Whether one told by its level plays, read once a second (`polledState`).
    let assertions: PlaybackAssertions
    nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    /// Whether Audio Recording lets a tap hear it (`AudioCapturePermission.allowsTaps`).
    let audioRecordingAllowed: @Sendable () -> Bool
    /// Its Now Playing report said it wasn't playing while it was heard: an
    /// app may report only while it's the Now Playing app (Qobuz's said
    /// "Paused" for half an hour while it played, Player Check, 2026-10-15),
    /// so its reports count no more.
    private var reportIsStale = false
    /// The report last checked against its level, by when it came.
    private var reportHeardAt: Date?
    static let probeQueue = DispatchQueue(label: "AutoHush.CheckedPlayer.level", qos: .userInitiated)
    /// Its ways' order in each window state, with its backups on; `nil`
    /// without backups: its ways are pressed in turn, as before them.
    let wayOrder: WayOrder?
    /// The state its window is in now (`AppWindows`, up to 1 s).
    let windowState: @Sendable (pid_t) async -> CheckResult.WindowState
    /// Whether a backup way may be pressed without macOS asking anything
    /// (Automation for its AppleScript, Accessibility for the others).
    let backupAllowed: @Sendable (WayOrder.Kind, pid_t) async -> Bool
    /// The ways tried in this muted pause, by their place in `wayOrder`
    /// (`pauseWhileMuted`): the Play/Pause key and the panel once only (the
    /// user, 2026-11-04); a pause or a play starts again.
    var mutedTried: Set<Int> = []
    /// When a play by the panel last failed (`panelPlayRest`).
    var panelPlayFailedAt: Date?
    /// Each pause or play begun counts one: one going down its ways stops
    /// once another has begun.
    var pressCalls = 0
    /// Which control paused and played it last (`PlayerControls`).
    nonisolated let lastUsed = OSAllocatedUnfairLock(initialState: LastControls())
    /// Its backup switches as they are now: its setup's, until Settings
    /// changes them (`setSwitches`).
    nonisolated let switches: OSAllocatedUnfairLock<BackupSwitches>
    let now: @Sendable () -> Date

    package init(setup: PlayerSetup, reports: NowPlayingReports? = CheckedPlayer.sharedReports, store: any PlayerSetupStore = DefaultsPlayerSetupStore()) {
        let switches = OSAllocatedUnfairLock(initialState: setup.switches)
        self.init(setup: setup, parts: Self.parts(for: setup, store: store, switches: switches), reports: reports, switches: switches)
    }

    init(setup: PlayerSetup, parts: Parts, reports: NowPlayingReports?,
         switches: OSAllocatedUnfairLock<BackupSwitches>? = nil,
         processIdentifier: (@Sendable () -> pid_t?)? = nil,
         processArguments: @escaping @Sendable (pid_t) -> [String] = { ProcessArguments.of($0) },
         openWithLaunchOption: @escaping @Sendable (URL) async -> Bool = CheckedPlayer.openWithLaunchOption,
         levelProbe: any AudioLevelProbing = ProcessTapLevelProbe(),
         soundOn: (@Sendable (pid_t) -> Bool)? = nil,
         assertionsHeld: @escaping @Sendable (pid_t) -> Set<PowerAssertion> = PlaybackAssertions.read,
         pressSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
         audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps },
         windowState: @escaping @Sendable (pid_t) async -> CheckResult.WindowState = CheckedPlayer.readWindowState(of:),
         backupAllowed: @escaping @Sendable (WayOrder.Kind, pid_t) async -> Bool = CheckedPlayer.mayPressBackup(_:pid:),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.setup = setup
        self.parts = parts
        self.switches = switches ?? OSAllocatedUnfairLock(initialState: setup.switches)
        self.wayOrder = Self.wayOrder(for: setup, backups: parts.backups)
        self.windowState = windowState
        self.backupAllowed = backupAllowed
        self.now = now
        self.reports = reports?.isAvailable == true ? reports : nil
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.processArguments = processArguments
        self.openWithLaunchOption = openWithLaunchOption
        self.levelProbe = levelProbe
        let sound = OwnedAudioProcesses()
        self.soundOn = soundOn ?? { sound.isPlayingSound(appPID: $0) }
        self.assertions = PlaybackAssertions(read: assertionsHeld)
        self.pressSleep = pressSleep
        self.audioRecordingAllowed = audioRecordingAllowed
        parts.toggleState?.set { [weak self] in await self?.sureState() ?? .unknown }
        parts.page?.otherSigns.set { [weak self] in await self?.stateBesidesPage() ?? .unknown }
        parts.hearing?.set { [weak self] pid in await self?.heardNow(pid) }
        parts.backupHearing?.set { [weak self] pid in await self?.heardNow(pid) }
        parts.mediaKeyState?.set { [weak self] in await self?.sureState() ?? .unknown }
    }

    /// Read where macOS's log can be read (an administrator's account),
    /// followed while a player asks.
    package static let sharedReports = NowPlayingReports()

    package func verifyControlAccess() async throws {
        var firstError: any Error?
        for way in parts.ways where !(way is PanelWay) {
            do {
                try await way.verifyControlAccess()
                return
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
        try await parts.ways.first { $0 is PanelWay }?.verifyControlAccess()
    }

    package func pause() async throws {
        if usesBackups { return try await pressByBackups(to: .paused) }
        try await press(to: .paused)
    }

    package func play() async throws {
        if usesBackups { return try await pressByBackups(to: .playing) }
        try await press(to: .playing)
    }

    /// No mute stands in if it's refused: its backups at once.
    package func pauseUncovered() async throws {
        if usesBackups { return try await pressByBackups(to: .paused, covered: false) }
        try await press(to: .paused)
    }

    /// By its ways that show nothing: never the Now Playing panel, which
    /// shows on screen and takes the keyboard; with its backups on, one way
    /// at a time, the panel once in each muted pause while "the panel while
    /// muted" is on (`pauseWhileMuted`).
    package func pauseQuietly() async throws {
        if usesBackups { return try await pauseWhileMuted() }
        try await press(to: .paused, quietly: true)
    }

    /// Presses by the first way that takes it, checked as that way allows
    /// (`sureState`; a page and a toggle judged by another sign check their
    /// own; with no sure sign at all, not checked): a way that fails, or
    /// whose press doesn't take, hands it to the next, the panel last
    /// (`quietly`: not the panel).
    private func press(to target: PlayerState, quietly: Bool = false) async throws {
        ownPressBegins()
        var firstError: any Error?
        var checkable: Bool?
        for (index, way) in parts.ways.enumerated() where !(quietly && way is PanelWay) {
            do {
                try await press(way, to: target, checkable: &checkable)
                if setup.ways.indices.contains(index), let kind = setup.ways[index].kind {
                    lastUsed.withLock { $0.note(WayOrder.Kind(kind), for: target) }
                }
                return
            } catch {
                logger.notice("\(self.name, privacy: .public): \(String(describing: type(of: way)), privacy: .public) failed: \(error)")
                firstError = firstError ?? error
            }
        }
        throw firstError ?? MusicPlayerError.playerCommandFailed(.pressFailed)
    }

    /// Presses by `way`, checked as it allows: a way that checks its own
    /// presses, or one whose press can't be checked (`checkable`, asked once
    /// per press at the first way that doesn't: a sign saying nothing now,
    /// as a report of Unknown, would only be waited on), as it is; any
    /// other through `PressCheck`, by `sureState`.
    func press(_ way: any MusicPlayer, to target: PlayerState, checkable: inout Bool?) async throws {
        if !way.checksItsPresses, checkable == nil {
            checkable = (!parts.signs.isEmpty || reports != nil) ? await sureState() != .unknown : false
        }
        if way.checksItsPresses || checkable != true {
            if target == .playing { try await way.play() } else { try await way.pause() }
        } else {
            try await PressCheck(name: "\(name) (\(type(of: way)))",
                                 press: { target in if target == .playing { try await way.play() } else { try await way.pause() } },
                                 state: { [self] in await self.sureState() }, sleep: pressSleep).press(to: target)
        }
    }

    package func volume() async -> Int? { await parts.volume?.volume() }

    package func setVolume(_ volume: Int) async throws { try await parts.volume?.setVolume(volume) }

    /// Its notification when its script announces each change, else read
    /// about once a second; when it stops, a mute its page made in place of
    /// a pause is lifted, so the app is never left silent.
    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        let observer = parts.announcing?.makeStateObserver(onChange: onChange)
            ?? PolledStateObserver(read: { [self] in await self.polledState() }, onChange: onChange)
        guard let page = parts.page else { return observer }
        return StoppingObserver(observer) { Task { await page.releaseMute() } }
    }

    package nonisolated var stateReportDelay: TimeInterval {
        parts.announcing != nil ? 0 : PolledStateObserver.reportDelay
    }

    /// Whether `release` has something to undo: its page's switch (its page
    /// way's, or the one its panel way reads), or its page's mute.
    package nonisolated var releasesOnQuit: Bool { parts.page != nil || parts.cluePage != nil }

    /// Lifts its page's mute in place of a pause, without playing anything.
    package func releaseMute() async {
        await parts.page?.releaseMute()
    }

    /// Turns back off the switch its page needed and lifts its page's mute,
    /// without playing anything: as AutoHush quits, or once another player
    /// is chosen and AutoHush holds no pause in it. Chosen again, its page's
    /// switch goes back on at its next look.
    package func release() async {
        await parts.page?.releaseMute()
        await parts.page?.releasePage()
        parts.cluePage?.release()
    }

    /// Controlled through a Now Playing row that doesn't follow it: only its
    /// sound tells how it is.
    package nonisolated var needsAudioLevels: Bool { parts.hearing != nil }

    /// What it last reported to Now Playing, unless that's stale (see
    /// `reportIsStale`): a report that it isn't playing while its output is
    /// open is checked once against its level (half a second of listening,
    /// with Audio Recording, not in AntiDot mode), at the first read that
    /// isn't `polled`.
    func reported(pid: pid_t, polled: Bool) async -> PlayerState? {
        guard !reportIsStale, let client = reports?.latest(of: bundleID), let state = client.state else { return nil }
        guard !polled, state != .playing, client.changed != reportHeardAt, tapsAllowed.withLock({ $0 }) else { return state }
        guard await soundOnNow(pid) else { return state }
        reportHeardAt = client.changed
        // Audio Recording asked on the probe's queue too, as `heardNow` asks it.
        let probe = levelProbe, allowed = audioRecordingAllowed
        guard await Self.probeQueue.run({ allowed() && probe.isAudible(appPID: pid) }) else { return state }
        reportIsStale = true
        logger.notice("\(self.name, privacy: .public)’s Now Playing report says \(client.reported ?? "", privacy: .public) while it’s heard: its reports count no more")
        return nil
    }
}
