import AppKit
import Foundation
import os
import AutoHushKit
import WebAppPlayers

// CheckedPlayer: its backups, pressed by the window's state (the user, 2026-11-04).
extension CheckedPlayer {
    /// A backup way's player, and which way it is.
    struct Backup: Sendable {
        let player: any MusicPlayer
        let kind: CheckResult.WayKind
    }

    /// How long a play by the panel that failed keeps it out of the next
    /// plays (the engine's retries, a second apart): it shows on screen.
    static let panelPlayRest: TimeInterval = 10

    /// Its ways' order with its backups (`WayOrder`): the chosen way, then
    /// each backup, with how its check found it; `nil` without backups.
    static func wayOrder(for setup: PlayerSetup, backups: [Backup]) -> WayOrder? {
        guard setup.usesBackups, !backups.isEmpty, let chosen = setup.ways.first?.kind else { return nil }
        func way(_ kind: CheckResult.WayKind) -> WayOrder.Way {
            WayOrder.Way(kind: kind, result: setup.wayResults.first { $0.kind == kind })
        }
        return WayOrder(ways: [way(chosen)] + backups.map { way($0.kind) })
    }

    /// Presses by its ways in their order for the window's state (`WayOrder`):
    ///
    /// - A pause by the first only: refused, AutoHush mutes it instead, and
    ///   its muted retries go on by the others (`pauseWhileMuted`). When it
    ///   can't be muted (AntiDot mode, no Audio Recording, a Chromium web
    ///   app's), down the order at once.
    /// - A play down the order at once (nothing stands in for a play); the
    ///   panel not again within `panelPlayRest` of a play it failed.
    ///
    /// Before each way after the first, its state is read again: a press
    /// that took late ends it, so a slow toggle isn't undone; each way then
    /// presses only from the opposite state. Another pause or play begun
    /// meanwhile ends it too. A backup macOS would ask something for
    /// (Automation, Accessibility) is passed over, and a way that can't
    /// press yet (its page's button not learned) hands on to the next. A
    /// failure throws the first way's error.
    func pressByBackups(to target: PlayerState) async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let call = pressCalls
        mutedTried = []
        // Looked at only when it changes the order.
        let state: CheckResult.WindowState? = wayOrder.dependsOnWindow(for: target) ? await windowState(pid) : nil
        let window = state.map { ", its window \($0.title)" } ?? ""
        var goesOn = target == .playing
        if !goesOn { goesOn = await !canBeMuted() }
        var firstError: (any Error)?
        var pressed = 0, learning = false
        var checkable: Bool?
        for index in wayOrder.order(in: state ?? .visible, for: target) {
            let kind = wayOrder.ways[index].kind
            if pressed > 0, !goesOn || pressCalls != call { break }
            if target == .playing, kind == .panel, let failed = panelPlayFailedAt, now().timeIntervalSince(failed) < Self.panelPlayRest { continue }
            guard let way = await allowedWay(index, kind: kind, pid: pid) else { continue }
            if pressed > 0 {
                // It took late: a press now could undo it.
                let now = await sureState()
                if target == .playing ? now == .playing : (now == .paused || now == .stopped) {
                    logger.notice("\(self.name, privacy: .public) is \(now.rawValue, privacy: .public) now: no backup pressed")
                    return
                }
            }
            pressed += 1
            do {
                try await press(way, to: target, checkable: &checkable)
                if index != 0 || state != nil {
                    logger.notice("\(self.name, privacy: .public): \(target == .playing ? "played" : "paused", privacy: .public) by its \(kind.rawValue, privacy: .public)\(index == 0 ? "" : " (a backup)", privacy: .public)\(window, privacy: .public)")
                }
                return
            } catch MusicPlayerError.stillLearning {
                logger.notice("\(self.name, privacy: .public): its \(kind.rawValue, privacy: .public) can’t press yet: the next way")
                learning = true
                pressed -= 1
            } catch {
                logger.notice("\(self.name, privacy: .public): its \(kind.rawValue, privacy: .public) failed\(window, privacy: .public): \(error)")
                firstError = firstError ?? error
                if kind == .panel, target == .playing { panelPlayFailedAt = now() }
                // Its muted retries start with the next way.
                if target == .paused, pressed == 1 { mutedTried.insert(index) }
            }
        }
        throw firstError ?? (learning ? MusicPlayerError.stillLearning : MusicPlayerError.playerCommandFailed(.pressFailed))
    }

    /// Muted in place of its pause, and still heard: one way, the next in
    /// the order for the window's state not yet tried in this pause, the
    /// quiet ways first (round again once all were tried), the panel last,
    /// once in the pause, while "the panel while muted" is on. AutoHush asks
    /// again only while it's still muted and heard, so each retry is one
    /// press: a resume meanwhile isn't followed by a pause.
    func pauseWhileMuted() async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let state: CheckResult.WindowState? = wayOrder.dependsOnWindow(for: .paused) ? await windowState(pid) : nil
        let order = wayOrder.order(in: state ?? .visible, for: .paused)
        let quiet = order.filter { wayOrder.ways[$0].kind != .panel }
        let panel = setup.panelWhileMuted ? order.filter { wayOrder.ways[$0].kind == .panel } : []
        if (quiet + panel).allSatisfy(mutedTried.contains) { mutedTried.subtract(quiet) }
        for index in quiet + panel where !mutedTried.contains(index) {
            mutedTried.insert(index)
            let kind = wayOrder.ways[index].kind
            guard let way = await allowedWay(index, kind: kind, pid: pid) else { continue }
            var checkable: Bool?
            do {
                try await press(way, to: .paused, checkable: &checkable)
                logger.notice("\(self.name, privacy: .public): paused by its \(kind.rawValue, privacy: .public)\(index == 0 ? "" : " (a backup)", privacy: .public) while muted")
                return
            } catch {
                logger.notice("\(self.name, privacy: .public): muted, its \(kind.rawValue, privacy: .public) failed: \(error)")
                throw error
            }
        }
        throw MusicPlayerError.playerCommandFailed(.pressFailed)
    }

    /// The player of its way at `index` (its chosen way at 0), unless it's a
    /// backup macOS would ask something for.
    private func allowedWay(_ index: Int, kind: CheckResult.WayKind, pid: pid_t) async -> (any MusicPlayer)? {
        guard index != 0 else { return parts.ways.first }
        guard await backupAllowed(kind, pid) else {
            logger.notice("\(self.name, privacy: .public): its \(kind.rawValue, privacy: .public) isn’t allowed without macOS asking: passed over")
            return nil
        }
        return parts.backups[index - 1].player
    }

    /// Whether AutoHush can mute it in place of a pause, as its mute asks
    /// (`ProcessPlayerMute`): not in AntiDot mode, with Audio Recording, and
    /// not a Chromium web app, whose sound is its browser's.
    private func canBeMuted() async -> Bool {
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
    /// already allowed; Accessibility for its page, menu or panel.
    package static func mayPressBackup(_ kind: CheckResult.WayKind, pid: pid_t) async -> Bool {
        await windowQueue.run {
            if kind == .script { return AutomationPermission(status: AutomationPermission.check(pid: pid, ask: false)) == .allowed }
            return AXIsProcessTrusted()
        }
    }

    private static let windowQueue = DispatchQueue(label: "AutoHush.CheckedPlayer.windows", qos: .userInitiated)
}
