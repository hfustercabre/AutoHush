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
/// answers, as Player Check judges it: its scripted state, its page's word
/// (while current), its menu's item, what it reported to Now Playing (only
/// where macOS's log can be read), else whether its sound is on.
package actor CheckedPlayer: MutingMusicPlayer {
    package nonisolated let setup: PlayerSetup

    package nonisolated var bundleID: String { setup.bundleID }
    package nonisolated var name: String { setup.name }
    package nonisolated var installedURL: URL? { setup.appURL }
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
    }

    private nonisolated let parts: Parts
    private let reports: NowPlayingReports?
    /// Its running process, if it runs: AutoHush never launches it.
    private let processIdentifier: @Sendable () -> pid_t?
    private let sound = OwnedAudioProcesses()
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

    package init(setup: PlayerSetup, reports: NowPlayingReports? = CheckedPlayer.sharedReports, store: any PlayerSetupStore = DefaultsPlayerSetupStore()) {
        self.init(setup: setup, parts: Self.parts(for: setup, store: store), reports: reports)
    }

    init(setup: PlayerSetup, parts: Parts, reports: NowPlayingReports?,
         processIdentifier: (@Sendable () -> pid_t?)? = nil, muter: any AudioMuting = ProcessTapMuter(),
         assertionHeld: @escaping @Sendable (pid_t) -> Bool = CheckedPlayer.holdsAssertion) {
        self.setup = setup
        self.parts = parts
        self.reports = reports?.isAvailable == true ? reports : nil
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.muter = muter
        self.assertionHeld = assertionHeld
    }

    /// Whether the app running as `pid`, or a process of its own, holds a
    /// keep-awake assertion (media apps hold one while they play).
    package static let holdsAssertion: @Sendable (pid_t) -> Bool = { pid in
        IOKitPowerAssertionReader().assertionsByProcess().contains { owner, assertions in
            !assertions.isEmpty && (owner == pid || ProcessResponsibility.isOwned(owner, by: pid))
        }
    }

    /// Read where macOS's log can be read (an administrator's account).
    package static let sharedReports = NowPlayingReports()

    /// The players of `setup`'s ways.
    static func parts(for setup: PlayerSetup, store: any PlayerSetupStore) -> Parts {
        var parts = Parts(ways: [], signs: [])
        var scripted: ScriptedAppPlayer?, menu: MenuPlayer?
        for way in setup.ways {
            switch way {
            case .script(let script):
                let player = ScriptedAppPlayer(bundleID: setup.bundleID, name: setup.name, setup: script,
                                               stateNotification: setup.stateNotification.map { Notification.Name($0) })
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
                parts.ways.append(PanelWay(setup: setup, remembered: remembered, store: store))
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
        guard let pid = processIdentifier() else { return .notRunning }
        if parts.mutes {
            let (state, unmute) = hush.read(playing: playsNow(pid), at: Date())
            if unmute {
                liftMute()
                logger.notice("\(self.name, privacy: .public): unmuted, as it was played again (or stopped after a sleep)")
            }
            return state
        }
        // The surest sign that answers.
        for sign in parts.signs {
            let state = await sign.playerState()
            if state != .unknown { return state }
        }
        if let reported = reports?.state(of: bundleID) { return reported }
        return sound.isPlayingSound(appPID: pid) ? .playing : .paused
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
        try await press { try await $0.pause() }
    }

    package func play() async throws {
        if parts.mutes {
            liftMute()
            hush.unmute()
            return
        }
        try await press { try await $0.play() }
    }

    /// Whether it plays now, for one that's muted: its keep-awake assertion
    /// once it has held one, else its sound output (open while it plays, and
    /// for some apps paused too).
    private func playsNow(_ pid: pid_t) -> Bool {
        if assertionHeld(pid) {
            assertionSeen = true
            return true
        }
        return assertionSeen ? false : sound.isPlayingSound(appPID: pid)
    }

    private func liftMute() {
        if let mutedPID { muter.unmute(appPID: mutedPID) }
        mutedPID = nil
    }

    /// Presses by the first way that takes it: a way that fails hands it to
    /// the next, the panel last.
    private func press(_ action: (any MusicPlayer) async throws -> Void) async throws {
        var firstError: (any Error)?
        for way in parts.ways {
            do {
                try await action(way)
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

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        if let announcing = parts.announcing { return announcing.makeStateObserver(onChange: onChange) }
        return PolledStateObserver(read: { [self] in await self.playerState() }, onChange: onChange)
    }

    package nonisolated var stateReportDelay: TimeInterval {
        parts.announcing != nil ? 0 : PolledStateObserver.reportDelay
    }

    /// Its page needed a switch turned on in its app.
    package nonisolated var releasesOnQuit: Bool { parts.page != nil || parts.mutes }

    /// Turns back off the switch its page needed, and lifts a mute, as
    /// AutoHush quits (a mute would end with it anyway).
    package func release() async {
        await parts.page?.releasePage()
        liftMute()
    }

    // MARK: Muted instead of paused

    package nonisolated var pausesByMuting: Bool { parts.mutes }

    /// Not in AntiDot mode, which taps no sound: then it can't be muted, and
    /// a mute under way is lifted.
    package nonisolated func allowTaps(_ allowed: Bool) {
        tapsAllowed.withLock { $0 = allowed }
        guard !allowed else { return }
        Task { await self.unmuteForGood() }
    }

    private func unmuteForGood() {
        liftMute()
        hush.unmute()
    }

    /// One that's muted reads as paused while muted; nothing more to mute.
    package func muteIfPlayingAnyway() async -> Bool { false }

    /// The Mac slept: AutoHush no longer holds the pause the mute stands for.
    /// It's lifted once the app stops (now, if it has), never while it plays.
    package func forgetPause() async {
        guard parts.mutes, hush.isMuted else { return }
        hush.forget()
        _ = await playerState()
    }
}
