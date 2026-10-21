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
/// Player Check judges by much the same signs, in its own order (the report
/// second, its level among them).
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

    /// Its ways' players, and which of them read its state, its volume, its
    /// notification.
    struct Parts: Sendable {
        /// The ways, in the setup's order (the panel last): each press goes
        /// to the first that takes it.
        var ways: [any MusicPlayer]
        /// Those that read its state, surest first: its script (when it has
        /// a state), its page, its menu.
        var signs: [any MusicPlayer]
        /// Its script, when it has a volume (fades).
        var volume: any MusicPlayer?
        /// Its script, when it announces each change (its notification).
        var announcing: any MusicPlayer?
        /// Its page's player, whose switch is released with it.
        var page: SafariWebAppPlayer?
        /// The page its panel way reads its player bar through
        /// (`PanelClues.page`), whose switch is released with it too.
        var cluePage: AccessibilityWebPage?
        /// Its panel row doesn't follow it (`PlayerSetup.panelRowIsStale`):
        /// the panel way asks its sound through this.
        var hearing: LateHearing?
        /// What a script that only toggles, with no state of its own, asks before it's sent.
        var toggleState: LateState?
    }

    private nonisolated let parts: Parts
    private let reports: NowPlayingReports?
    /// Its running process, if it runs: AutoHush never launches it.
    let processIdentifier: @Sendable () -> pid_t?
    /// What its process was opened with (`needsReopen`).
    let processArguments: @Sendable (pid_t) -> [String]
    /// Opens it with the launch option, in the background (`reopen`).
    let openWithLaunchOption: @Sendable (URL) async -> Bool
    /// Whether its sound output is on (a process of its own plays).
    private let soundOn: @Sendable (pid_t) -> Bool
    private let levelProbe: any AudioLevelProbing
    private let pressSleep: VolumeFader.Sleep
    private let logger = AutoHushLogger(category: "CheckedPlayer")
    /// Whether one told by its level plays, read once a second (`polledState`).
    private var assertions: PlaybackAssertions
    private nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
    /// Whether Audio Recording lets a tap hear it (`AudioCapturePermission.allowsTaps`).
    private let audioRecordingAllowed: @Sendable () -> Bool
    /// Its Now Playing report said it wasn't playing while it was heard: an
    /// app may report only while it's the Now Playing app (Qobuz's said
    /// "Paused" for half an hour while it played, Player Check, 2026-10-15),
    /// so its reports count no more.
    private var reportIsStale = false
    /// The report last checked against its level, by when it came.
    private var reportHeardAt: Date?
    private static let probeQueue = DispatchQueue(label: "AutoHush.CheckedPlayer.level", qos: .userInitiated)

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

    /// The players of `setup`'s ways.
    static func parts(for setup: PlayerSetup, store: any PlayerSetupStore) -> Parts {
        var parts = Parts(ways: [], signs: [])
        var scripted: ScriptedAppPlayer?, menu: MenuPlayer?
        for way in setup.ways {
            switch way {
            case .script(let script):
                // One that only toggles, with no state, asks the app's other signs.
                let late = script.state == nil ? LateState() : nil
                if let late { parts.toggleState = late }
                let player = ScriptedAppPlayer(bundleID: setup.bundleID, name: setup.name, setup: script,
                                               stateNotification: setup.stateNotification.map { Notification.Name($0) },
                                               toggleState: { await late?.state() ?? .unknown })
                scripted = player
                parts.ways.append(player)
                if script.hasVolume { parts.volume = player }
                if player.stateNotification != nil { parts.announcing = player }
            case .menu(let menuName):
                let player = MenuPlayer(profile: .found(bundleID: setup.bundleID, name: setup.name, menuName: menuName))
                menu = player
                parts.ways.append(player)
            case .page(let access):
                let player = SafariWebAppPlayer(app: SafariWebApp(bundleID: setup.bundleID, name: setup.name, url: setup.appURL),
                                                kind: .app, page: AccessibilityWebPage(access: access), canMute: access.browserID == nil)
                parts.page = player
                parts.ways.append(player)
            case .panel(let remembered):
                let hearing = setup.panelRowIsStale == true ? LateHearing() : nil
                parts.hearing = hearing
                var playerBar: (@Sendable (pid_t) -> [String])?
                if let clue = setup.panelClues?.page {
                    let page = AccessibilityWebPage(access: clue.access), labels = Set(clue.labels)
                    parts.cluePage = page
                    playerBar = { page.playerBarTexts(pid: $0, labels: labels) }
                }
                parts.ways.append(PanelWay(setup: setup, remembered: remembered, store: store, playerBar: playerBar, hearing: hearing))
            case .mute:
                break // a `MutedApp`'s
            }
        }
        if let scripted, scripted.setup.state != nil { parts.signs.append(scripted) }
        if let page = parts.page { parts.signs.append(page) }
        if let menu { parts.signs.append(menu) }
        return parts
    }

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

    /// Asked when AutoHush is about to pause or play it (and as it starts):
    /// its level may be listened to then.
    package func playerState() async -> PlayerState {
        await state(polled: false)
    }

    /// For its observer, about once a second: its page is read as a web
    /// app's observer reads it (less often while it's silent), and its sound
    /// is never listened to (see `sureState`).
    func polledState() async -> PlayerState {
        await state(polled: true)
    }

    private func state(polled: Bool) async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        let sure = await sureState(pid: pid, polled: polled)
        if sure != .unknown { return sure }
        // Told by its level, which isn't listened to now: an open output
        // tells nothing (Qobuz keeps its own open while paused).
        let soundIsOn = await soundOnNow(pid)
        if polled, parts.hearing != nil { return soundIsOn ? .unknown : .paused }
        return soundIsOn ? .playing : .paused
    }

    /// Whether its sound output is on, read on the probe's queue, never on
    /// Swift's shared threads (DEVELOPMENT.md).
    private func soundOnNow(_ pid: pid_t) async -> Bool {
        let soundOn = soundOn
        return await Self.probeQueue.run { soundOn(pid) }
    }

    /// What its sure signs say: its ways' own (its script's state, its
    /// page's word, its menu's item), else, for one whose Now Playing row
    /// doesn't follow it, its level (`heardNow`), else what it reported to
    /// Now Playing; `.unknown` when none answers. Whether its output is open
    /// can't tell: an output stays open for seconds after a pause. Its
    /// presses are checked by this, and a script that only toggles asks it.
    func sureState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        return await sureState(pid: pid, polled: false)
    }

    /// `polled`: read once a second, its sound isn't listened to (the user,
    /// 2026-10-16: else macOS's recording dot stays on all day): one told by
    /// its level goes by its keep-awake assertion then, and a report isn't
    /// checked against its level.
    private func sureState(pid: pid_t, polled: Bool) async -> PlayerState {
        for sign in parts.signs {
            let state: PlayerState
            if polled, let page = sign as? SafariWebAppPlayer {
                state = await page.polledPlayerState()
            } else {
                state = await sign.playerState()
            }
            if state != .unknown { return state }
        }
        // Its Now Playing row (and report) doesn't follow it: only its sound
        // tells, and between decisions its keep-awake assertion.
        if parts.hearing != nil {
            if polled {
                let soundOn = soundOn, current = assertions
                let (state, read) = await Self.probeQueue.run { () -> (PlayerState, PlaybackAssertions) in
                    var assertions = current
                    let state = assertions.state(of: pid, soundOn: { soundOn(pid) })
                    return (state, assertions)
                }
                assertions = read
                return state
            }
            return await heardNow(pid).map { $0 ? .playing : .paused } ?? .unknown
        }
        return await reported(pid: pid, polled: polled) ?? .unknown
    }

    /// Whether it's heard now, by its level (half a second of listening),
    /// only when AutoHush is about to pause or play it, or checks a press:
    /// one with no sound output open isn't; `nil` without Audio Recording
    /// or in AntiDot mode, which taps no sound.
    func heardNow(_ pid: pid_t) async -> Bool? {
        guard await soundOnNow(pid) else { return false }
        guard tapsAllowed.withLock({ $0 }) else { return nil }
        // Audio Recording asked on the probe's queue too: TCC answers by IPC.
        let probe = levelProbe, allowed = audioRecordingAllowed
        return await Self.probeQueue.run { allowed() ? probe.isAudible(appPID: pid) : nil }
    }

    /// What it last reported to Now Playing, unless that's stale (see
    /// `reportIsStale`): a report that it isn't playing while its output is
    /// open is checked once against its level (half a second of listening,
    /// with Audio Recording, not in AntiDot mode), at the first read that
    /// isn't `polled`.
    private func reported(pid: pid_t, polled: Bool) async -> PlayerState? {
        guard !reportIsStale, let client = reports?.latest(of: bundleID), let state = client.state else { return nil }
        guard !polled, state != .playing, client.changed != reportHeardAt, tapsAllowed.withLock({ $0 }) else { return state }
        guard await soundOnNow(pid) else { return state }
        reportHeardAt = client.changed
        let probe = levelProbe
        guard await Self.probeQueue.run({ probe.isAudible(appPID: pid) }) else { return state }
        reportIsStale = true
        logger.notice("\(self.name, privacy: .public)’s Now Playing report says \(client.reported ?? "", privacy: .public) while it’s heard: its reports count no more")
        return nil
    }

    package func pause() async throws {
        try await press(to: .paused)
    }

    package func play() async throws {
        try await press(to: .playing)
    }

    /// Presses by the first way that takes it, checked as that way allows
    /// (`sureState`; a page and a toggle judged by another sign check their
    /// own; with no sure sign at all, not checked): a way that fails, or
    /// whose press doesn't take, hands it to the next, the panel last.
    private func press(to target: PlayerState) async throws {
        var firstError: any Error?
        let checkable = !parts.signs.isEmpty || reports != nil
        for way in parts.ways {
            do {
                if way.checksItsPresses || !checkable {
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

    /// Turns back off the switch its page needed and lifts its page's mute,
    /// without playing anything: as AutoHush quits, or once another player
    /// is chosen and AutoHush holds no pause in it. Chosen again, its page's
    /// switch goes back on at its next look.
    package func releaseMute() async {
        await parts.page?.releaseMute()
    }

    package func release() async {
        await parts.page?.releaseMute()
        await parts.page?.releasePage()
        parts.cluePage?.release()
    }

    /// Controlled through a Now Playing row that doesn't follow it: only its
    /// sound tells how it is.
    package nonisolated var needsAudioLevels: Bool { parts.hearing != nil }

    // MARK: Its page's mute in place of a pause

    /// Not in AntiDot mode, which taps no sound: then it isn't listened to,
    /// its page can't mute it in place of a pause, and a mute under way is
    /// lifted.
    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        parts.page?.allowTaps(allowed)
        guard !allowed, let page = parts.page else { return }
        Task { await page.releaseMute() }
    }

    /// Its page's (an ad its site won't pause, its button saying "Play"
    /// meanwhile).
    package func muteIfPlayingAnyway() async -> Bool {
        guard let page = parts.page else { return false }
        return await page.muteIfPlayingAnyway()
    }

    /// The Mac slept: AutoHush no longer holds the pause its page's mute
    /// stands for, lifted once the page is paused for real, or silent.
    package func forgetPause() async {
        await parts.page?.forgetPause()
    }
}
