import AppKit
import Foundation
import os
import AutoHushKit
import MenuPlayers
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
    var reportIsStale = false
    /// The report last checked against its level, by when it came.
    var reportHeardAt: Date?
    static let probeQueue = DispatchQueue(label: "AutoHush.CheckedPlayer.level", qos: .userInitiated)

    package init(setup: PlayerSetup, reports: NowPlayingReports? = CheckedPlayer.sharedReports, store: any PlayerSetupStore = DefaultsPlayerSetupStore()) {
        self.init(setup: setup, parts: Self.parts(for: setup, store: store), reports: reports)
    }

    init(setup: PlayerSetup, parts: Parts, reports: NowPlayingReports?,
         processIdentifier: (@Sendable () -> pid_t?)? = nil,
         processArguments: @escaping @Sendable (pid_t) -> [String] = { ProcessArguments.of($0) },
         openWithLaunchOption: @escaping @Sendable (URL) async -> Bool = CheckedPlayer.openWithLaunchOption,
         levelProbe: any AudioLevelProbing = ProcessTapLevelProbe(),
         soundOn: (@Sendable (pid_t) -> Bool)? = nil,
         assertionsHeld: @escaping @Sendable (pid_t) -> Set<PowerAssertion> = PlaybackAssertions.read,
         pressSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) },
         audioRecordingAllowed: @escaping @Sendable () -> Bool = { AudioCapturePermission.allowsTaps }) {
        self.setup = setup
        self.parts = parts
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
        parts.hearing?.set { [weak self] pid in await self?.heardNow(pid) }
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
        try await press(to: .paused)
    }

    package func play() async throws {
        try await press(to: .playing)
    }

    /// By its ways that show nothing: never the Now Playing panel, which
    /// shows on screen and takes the keyboard.
    package func pauseQuietly() async throws {
        try await press(to: .paused, quietly: true)
    }

    /// Presses by the first way that takes it, checked as that way allows
    /// (`sureState`; a page and a toggle judged by another sign check their
    /// own; with no sure sign at all, not checked): a way that fails, or
    /// whose press doesn't take, hands it to the next, the panel last
    /// (`quietly`: not the panel).
    private func press(to target: PlayerState, quietly: Bool = false) async throws {
        var firstError: any Error?
        // A sign that says nothing now (a Now Playing report of Unknown:
        // Apple TV's trailers) would only be waited on: not checked then.
        // Asked once, at the first way that doesn't check its own presses.
        var checkable: Bool?
        for way in parts.ways where !(quietly && way is PanelWay) {
            do {
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
                return
            } catch {
                logger.notice("\(self.name, privacy: .public): \(String(describing: type(of: way)), privacy: .public) failed: \(error)")
                firstError = firstError ?? error
            }
        }
        throw firstError ?? MusicPlayerError.playerCommandFailed(.pressFailed)
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
}
