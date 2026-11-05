import AppKit
import Foundation
import os
import AutoHushKit
import WebAppPlayers

// CheckedPlayer: its backups, pressed by the window's state (`BackupRouting`, the user, 2026-11-04).
extension CheckedPlayer: BackupRouting, ControlsReporting {
    /// A backup way's player, and which way it is.
    struct Backup: Sendable {
        let player: any MusicPlayer
        let kind: WayOrder.Kind
    }

    /// Its ways' order with its backups (`WayOrder`): the chosen way, then
    /// each backup, with how its check found it; `nil` without backups.
    /// Made whether they're on or not: `usesBackups` says at each press.
    static func wayOrder(for setup: PlayerSetup, backups: [Backup]) -> WayOrder? {
        guard !backups.isEmpty, let chosen = setup.ways.first?.kind else { return nil }
        func way(_ kind: WayOrder.Kind) -> WayOrder.Way {
            WayOrder.Way(kind: kind, result: kind.checked.flatMap { checked in setup.wayResults.first { $0.kind == checked } })
        }
        return WayOrder(ways: [way(WayOrder.Kind(chosen))] + backups.map { way($0.kind) })
    }

    /// Whether it gets the keyboard's Play/Pause key as a backup
    /// (`MediaKeyWay`), pressed while its backups are on: once checked since
    /// they were kept (2026-11-04); one added before keeps its one way until
    /// it's checked again (the user, 2026-11-04).
    static func hasMediaKey(_ setup: PlayerSetup) -> Bool {
        !setup.wayResults.isEmpty
    }

    /// Its backups are pressed now: it has some, and their switch is on.
    nonisolated var usesBackups: Bool {
        wayOrder != nil && switches.withLock { $0.usesBackups }
    }

    /// Sets its backup switches (Settings → Media Player): its next press
    /// follows them; its setup is saved by `CheckedPlayers`.
    package nonisolated func setSwitches(_ new: BackupSwitches) {
        switches.withLock { $0 = new }
    }

    /// Its setup with its switches as they are now: what it's kept for
    /// (`CheckedPlayers`), so a change to them keeps the player.
    package nonisolated var setupNow: PlayerSetup {
        var now = setup
        let current = switches.withLock { $0 }
        now.usesBackups = current.usesBackups
        now.panelWhileMuted = current.panelWhileMuted
        return now
    }


    /// Its chosen way at 0, then its backups.
    func way(at index: Int) -> any MusicPlayer {
        index == 0 ? parts.ways[0] : parts.backups[index - 1].player
    }

    var panelWhileMuted: Bool { switches.withLock { $0.panelWhileMuted } }

    /// Its chosen way and the backups its setup keeps (the Play/Pause key
    /// once checked since backups were kept), whether they're on or not,
    /// and which paused and played it last.
    package nonisolated var controls: PlayerControls {
        func control(_ kind: CheckResult.WayKind) -> PlayerControls.Control {
            .init(kind: WayOrder.Kind(kind), result: setup.wayResults.first { $0.kind == kind })
        }
        let main = setup.ways.first?.kind.map(control) ?? .init(kind: .panel, result: nil)
        let keyed = setup.wayResults.isEmpty ? [] : [PlayerControls.Control(kind: .mediaKey, result: nil)]
        let kept = setup.backups.compactMap(\.kind).map(control)
        // The key before the panel, as they're pressed.
        let backups = kept.filter { $0.kind != .panel } + keyed + kept.filter { $0.kind == .panel }
        return PlayerControls(main: main, backups: backups,
                              switches: switches.withLock { $0 },
                              needsCheckAgain: setup.wayResults.isEmpty, last: lastUsed.withLock { $0 })
    }

    /// Whether AutoHush can mute it in place of a pause, as its mute asks
    /// (`ProcessPlayerMute`): not in AntiDot mode, with Audio Recording, and
    /// not a Chromium web app, whose sound is its browser's.
    func canBeMuted() async -> Bool {
        guard tapsAllowed.withLock({ $0 }), !isChromiumWebApp else { return false }
        let allowed = audioRecordingAllowed
        return await Self.probeQueue.run { allowed() }
    }

    /// A Chromium browser's web app (its page served by the browser).
    private var isChromiumWebApp: Bool {
        (setup.ways + setup.backups).contains { if case .page(let access) = $0 { access.browserID != nil } else { false } }
    }

    /// Where its window is now: hidden, as the app says (at once), else as
    /// Add an App's check tells it (`AppWindows.state`, about 70 ms, up to
    /// 1 s); with no window, closed.
    package static func readWindowState(of pid: pid_t) async -> CheckResult.WindowState {
        await windowQueue.run {
            guard let app = NSRunningApplication(processIdentifier: pid) else { return .windowsClosed }
            if app.isHidden { return .hidden }
            return AppWindows.state(of: app) ?? .windowsClosed
        }
    }

    /// Whether a backup may be pressed, or a backup's AppleScript read,
    /// without macOS asking for anything: Automation for its AppleScript,
    /// already allowed; Accessibility for its page, menu or panel, and for
    /// posting the Play/Pause key.
    static func mayPressBackup(_ kind: WayOrder.Kind, pid: pid_t) async -> Bool {
        await windowQueue.run {
            switch kind {
            case .script: AutomationPermission(status: AutomationPermission.check(pid: pid, ask: false)) == .allowed
            case .mediaKey: CGPreflightPostEventAccess()
            case .menu, .page, .panel: AXIsProcessTrusted()
            }
        }
    }

    private static let windowQueue = DispatchQueue(label: "AutoHush.CheckedPlayer.windows", qos: .userInitiated)
}
