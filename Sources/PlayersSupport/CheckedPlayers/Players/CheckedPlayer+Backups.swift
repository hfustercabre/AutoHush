import AppKit
import Foundation
import os
import AutoHushKit
import WebAppPlayers

// CheckedPlayer: its backups, pressed by the window's state (`BackupRouting`, the user, 2026-11-04).
extension CheckedPlayer: BackupRouting {
    /// A backup way's player, and which way it is.
    struct Backup: Sendable {
        let player: any MusicPlayer
        let kind: WayOrder.Kind
    }

    /// Its ways' order with its backups (`WayOrder`): the chosen way, then
    /// each backup, with how its check found it; `nil` without backups.
    static func wayOrder(for setup: PlayerSetup, backups: [Backup]) -> WayOrder? {
        guard setup.usesBackups, !backups.isEmpty, let chosen = setup.ways.first?.kind else { return nil }
        func way(_ kind: WayOrder.Kind) -> WayOrder.Way {
            WayOrder.Way(kind: kind, result: kind.checked.flatMap { checked in setup.wayResults.first { $0.kind == checked } })
        }
        return WayOrder(ways: [way(WayOrder.Kind(chosen))] + backups.map { way($0.kind) })
    }

    /// Whether it gets the keyboard's Play/Pause key as a backup
    /// (`MediaKeyWay`): with its backups on, once checked since they were
    /// kept (2026-11-04); one added before keeps its one way until it's
    /// checked again (the user, 2026-11-04).
    static func hasMediaKey(_ setup: PlayerSetup) -> Bool {
        setup.usesBackups && !setup.wayResults.isEmpty
    }


    /// Its chosen way at 0, then its backups.
    func way(at index: Int) -> any MusicPlayer {
        index == 0 ? parts.ways[0] : parts.backups[index - 1].player
    }

    var panelWhileMuted: Bool { setup.panelWhileMuted }

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
