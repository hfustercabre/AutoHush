import AppKit
import Foundation
import os
import AutoHushKit
import MenuPlayers
import ScriptablePlayers
import WebAppPlayers

/// An app added through a check (`PlayerSetup`), controlled by the ways that
/// worked there, the surest first: its AppleScript, its page's Play/Pause,
/// its playback menu, and only when none of them works, its row in the Now
/// Playing panel (the user, 2026-10-15). Its state is the surest sign that
/// answers: its scripted state, its page's word (while current), its menu's
/// item, what it reported to Now Playing (only where macOS's log can be
/// read, and not once it's found stale), else whether its sound is on.
/// Player Check judges by much the same signs, in its own order (the report
/// second, its level among them).
///
/// It checks its own presses: each by the way that made it, against those
/// signs (`sureState`) and never by its sound alone, since an output stays
/// open for seconds after a pause; a page checks its own, and a mute always
/// takes.
package actor CheckedPlayer: MutingMusicPlayer {
    package nonisolated let setup: PlayerSetup

    package nonisolated var bundleID: String { setup.bundleID }
    package nonisolated var name: String { setup.name }
    /// Where it was checked, else where macOS finds it now (it was moved);
    /// `nil` while it isn't installed.
    package nonisolated var installedURL: URL? { Self.installedURL(of: setup) }
    package nonisolated var kind: MusicPlayerKind { .checkedApp }
    /// Muted only, it needs Audio Recording, as AutoHush's own hearing does.
    package nonisolated var controlPermission: Permission {
        switch setup.ways.first {
        case .script?: .automation(player: name)
        case .mute?: .systemAudioRecording
        default: .accessibility(player: name)
        }
    }
    package nonisolated var canFade: Bool { parts.volume?.canFade == true }
    /// Checked here (see above): `PressCheck` doesn't check it again.
    package nonisolated var checksItsPresses: Bool { true }

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
        var volume: (any MusicPlayer)?
        /// Its script, when it announces each change (its notification).
        var announcing: (any MusicPlayer)?
        /// Its page's player, whose switch is released with it.
        var page: SafariWebAppPlayer?
        /// It's muted instead of paused: no way pauses it (`PlayerSetup.Way.mute`).
        var mutes = false
        /// Its panel row doesn't follow it (`PlayerSetup.panelRowIsStale`):
        /// the panel way asks its sound through this.
        var hearing: LateHearing?
        /// What a script that only toggles, with no state of its own, asks before it's sent.
        var toggleState: LateState?
    }

    private nonisolated let parts: Parts
    private let reports: NowPlayingReports?
    /// Its running process, if it runs: AutoHush never launches it.
    private let processIdentifier: @Sendable () -> pid_t?
    /// Whether its sound output is on (a process of its own plays).
    private let soundOn: @Sendable (pid_t) -> Bool
    private let levelProbe: any AudioLevelProbing
    private let pressSleep: VolumeFader.Sleep
    private let logger = AutoHushLogger(category: "CheckedPlayer")
    /// For one that's muted instead of paused: the mute, what it stands for,
    /// and whether it plays now (its keep-awake assertion, once it has shown
    /// one: Qobuz holds one only while it plays; its sound output before).
    private let muter: any AudioMuting
    private var hush = MuteState()
    private var mutedPID: pid_t?
    private let assertionHeld: @Sendable (pid_t) -> Bool
    private var assertionSeen = false
    private nonisolated let tapsAllowed = OSAllocatedUnfairLock(initialState: true)
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
         processIdentifier: (@Sendable () -> pid_t?)? = nil, muter: any AudioMuting = ProcessTapMuter(),
         levelProbe: any AudioLevelProbing = ProcessTapLevelProbe(),
         soundOn: (@Sendable (pid_t) -> Bool)? = nil,
         assertionHeld: @escaping @Sendable (pid_t) -> Bool = CheckedPlayer.holdsAssertion,
         pressSleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) }) {
        self.setup = setup
        self.parts = parts
        self.reports = reports?.isAvailable == true ? reports : nil
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.muter = muter
        self.levelProbe = levelProbe
        let sound = OwnedAudioProcesses()
        self.soundOn = soundOn ?? { sound.isPlayingSound(appPID: $0) }
        self.assertionHeld = assertionHeld
        self.pressSleep = pressSleep
        parts.toggleState?.set { [weak self] in await self?.sureState() ?? .unknown }
        parts.hearing?.set { [weak self] pid in await self?.heardNow(pid) }
    }

    /// Whether the app running as `pid`, or a process of its own, holds a
    /// keep-awake assertion (media apps hold one while they play).
    package static let holdsAssertion: @Sendable (pid_t) -> Bool = { pid in
        IOKitPowerAssertionReader().assertionsByProcess().contains { owner, assertions in
            !assertions.isEmpty && (owner == pid || ProcessResponsibility.isOwned(owner, by: pid))
        }
    }

    /// Read where macOS's log can be read (an administrator's account),
    /// followed while a player asks.
    package static let sharedReports = NowPlayingReports()

    /// Where `setup`'s app is: where it was checked, else where Launch
    /// Services finds it (moved since); `nil` while it isn't installed.
    package static func installedURL(of setup: PlayerSetup) -> URL? {
        if FileManager.default.fileExists(atPath: setup.appURL.path) { return setup.appURL }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: setup.bundleID)
    }

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
                parts.ways.append(PanelWay(setup: setup, remembered: remembered, store: store, hearing: hearing))
            case .mute:
                parts.mutes = true
            }
        }
        if let scripted, scripted.setup.state != nil { parts.signs.append(scripted) }
        if let page = parts.page { parts.signs.append(page) }
        if let menu { parts.signs.append(menu) }
        return parts
    }

    package func verifyControlAccess() async throws {
        if parts.mutes {
            guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
            return
        }
        var firstError: (any Error)?
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

    package func playerState() async -> PlayerState {
        await state(polled: false)
    }

    /// For its observer, about once a second: its page is read as a web
    /// app's observer reads it (less often while it's silent).
    func polledState() async -> PlayerState {
        await state(polled: true)
    }

    private func state(polled: Bool) async -> PlayerState {
        guard let pid = processIdentifier() else {
            // Quit while muted: what the mute stood for goes with it.
            if parts.mutes { endMute() }
            return .notRunning
        }
        if parts.mutes {
            // Opened again since it was muted: that mute was the old process's.
            if let mutedPID, mutedPID != pid { endMute() }
            let (state, unmute) = hush.read(playing: playsNow(pid), at: Date())
            if unmute {
                liftMute()
                logger.notice("\(self.name, privacy: .public): unmuted, as it was played again (or stopped after a sleep)")
            }
            return state
        }
        let sure = await sureState(pid: pid, polled: polled)
        if sure != .unknown { return sure }
        return soundOn(pid) ? .playing : .paused
    }

    /// What its sure signs say: its ways' own (its script's state, its
    /// page's word, its menu's item), else what it reported to Now Playing;
    /// `.unknown` when none answers. Its sound alone can't tell: an output
    /// stays open for seconds after a pause. Its presses are checked by
    /// this, and a script that only toggles asks it.
    func sureState() async -> PlayerState {
        guard let pid = processIdentifier() else { return .notRunning }
        return await sureState(pid: pid, polled: false)
    }

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
        // Its Now Playing row (and report) doesn't follow it: only its sound tells.
        if parts.hearing != nil {
            return await heardNow(pid).map { $0 ? .playing : .paused } ?? .unknown
        }
        return await reported(pid: pid) ?? .unknown
    }

    /// Whether it's heard now, by its level (half a second of listening):
    /// one with no sound output open isn't; `nil` without Audio Recording or
    /// in AntiDot mode, which taps no sound.
    func heardNow(_ pid: pid_t) async -> Bool? {
        guard soundOn(pid) else { return false }
        guard tapsAllowed.withLock({ $0 }) else { return nil }
        let probe = levelProbe
        return await Self.probeQueue.run { probe.isAudible(appPID: pid) }
    }

    /// What it last reported to Now Playing, unless that's stale (see
    /// `reportIsStale`): a report that it isn't playing while its output is
    /// open is checked once against its level (half a second of listening,
    /// with Audio Recording, not in AntiDot mode).
    private func reported(pid: pid_t) async -> PlayerState? {
        guard !reportIsStale, let client = reports?.latest(of: bundleID), let state = client.state else { return nil }
        guard state != .playing, client.changed != reportHeardAt, tapsAllowed.withLock({ $0 }),
              soundOn(pid) else { return state }
        reportHeardAt = client.changed
        let probe = levelProbe
        guard await Self.probeQueue.run({ probe.isAudible(appPID: pid) }) else { return state }
        reportIsStale = true
        logger.notice("\(self.name, privacy: .public)'s Now Playing report says \(client.reported ?? "", privacy: .public) while it's heard: its reports count no more")
        return nil
    }

    package func pause() async throws {
        if parts.mutes {
            guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
            guard tapsAllowed.withLock({ $0 }), muter.mute(appPID: pid) else {
                throw MusicPlayerError.playerCommandFailed(.muteUnavailable)
            }
            mutedPID = pid
            hush.mute()
            return
        }
        try await press(to: .paused)
    }

    package func play() async throws {
        if parts.mutes {
            endMute()
            return
        }
        try await press(to: .playing)
    }

    /// Whether it plays now, for one that's muted: its keep-awake assertion
    /// once it has held one, else its sound output (open while it plays, and
    /// for some apps paused too).
    private func playsNow(_ pid: pid_t) -> Bool {
        if assertionHeld(pid) {
            assertionSeen = true
            return true
        }
        return assertionSeen ? false : soundOn(pid)
    }

    private func liftMute() {
        if let mutedPID { muter.unmute(appPID: mutedPID) }
        mutedPID = nil
    }

    /// Unmuted, and nothing left of what the mute stood for.
    private func endMute() {
        liftMute()
        hush.unmute()
    }

    /// Presses by the first way that takes it, checked as that way allows
    /// (`sureState`; a page checks its own; with no sure sign at all, not
    /// checked): a way that fails, or whose press doesn't take, hands it to
    /// the next, the panel last.
    private func press(to target: PlayerState) async throws {
        var firstError: (any Error)?
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

    package func volume() async -> Int? { parts.mutes ? nil : await parts.volume?.volume() }

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

    /// Whether `release` has something to undo: its page's switch, or a mute
    /// (its own, or its page's).
    package nonisolated var releasesOnQuit: Bool { parts.page != nil || parts.mutes }

    /// Turns back off the switch its page needed and lifts a mute, its own
    /// or its page's, without playing anything: as AutoHush quits, or once
    /// another player is chosen and AutoHush holds no pause in it. Chosen
    /// again, its page's switch goes back on at its next look.
    package func release() async {
        await parts.page?.releaseMute()
        await parts.page?.releasePage()
        endMute()
    }

    // MARK: Muted instead of paused

    package nonisolated var pausesByMuting: Bool { parts.mutes }
    /// Muted only, or controlled through a Now Playing row that doesn't
    /// follow it: only its sound tells how it is.
    package nonisolated var needsAudioLevels: Bool { parts.mutes || parts.hearing != nil }

    /// Not in AntiDot mode, which taps no sound: then it can't be muted (nor
    /// its page in place of a pause), and a mute under way is lifted.
    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        parts.page?.allowTaps(allowed)
        guard !allowed else { return }
        Task { await self.unmuteForGood() }
    }

    private func unmuteForGood() async {
        endMute()
        await parts.page?.releaseMute()
    }

    /// Its page's (an ad its site won't pause, its button saying "Play"
    /// meanwhile). One that's muted instead of paused reads as paused while
    /// muted: nothing more to mute.
    package func muteIfPlayingAnyway() async -> Bool {
        guard !parts.mutes, let page = parts.page else { return false }
        return await page.muteIfPlayingAnyway()
    }

    /// The Mac slept: AutoHush no longer holds the pause a mute stands for.
    /// Its page's mute is lifted once the page is paused for real, or
    /// silent; its own once it has been stopped for `MuteState.stopTime`,
    /// never while it plays.
    package func forgetPause() async {
        await parts.page?.forgetPause()
        guard parts.mutes, hush.isMuted else { return }
        hush.forget()
        _ = await playerState()
    }
}
