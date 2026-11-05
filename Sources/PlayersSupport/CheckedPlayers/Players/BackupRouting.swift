import Foundation
import os
import AutoHushKit

/// A player pressed by its ways in their order for its window's state
/// (`WayOrder`): an app added with Add an App, with the other ways that
/// worked in its check (`CheckedPlayer`, the user, 2026-11-04), or a
/// built-in player with the ways measured for it (`BackedUpPlayer`, the
/// user, 2026-11-05). Its way at 0 is its own, its backups after it.
protocol BackupRouting: Actor {
    var name: String { get }
    /// Its ways' order in each window state; `nil` without backups.
    var wayOrder: WayOrder? { get }
    /// Its running process, if it runs.
    var processIdentifier: @Sendable () -> pid_t? { get }
    /// The state its window is in now.
    var windowState: @Sendable (pid_t) async -> CheckResult.WindowState { get }
    /// Whether a backup way may be pressed without macOS asking anything.
    var backupAllowed: @Sendable (WayOrder.Kind, pid_t) async -> Bool { get }
    var now: @Sendable () -> Date { get }
    var logger: AutoHushLogger { get }
    /// The ways tried in this muted pause, by their place in `wayOrder`
    /// (`pauseWhileMuted`); a pause or a play starts again.
    var mutedTried: Set<Int> { get set }
    /// Each pause or play begun counts one: one going down its ways stops
    /// once another has begun.
    var pressCalls: Int { get set }
    /// When a play by the panel last failed (`panelPlayRest`).
    var panelPlayFailedAt: Date? { get set }
    /// Whether the panel may be pressed while it's muted (its switch).
    var panelWhileMuted: Bool { get }
    /// The player of its way at `index` in `wayOrder` (its own at 0).
    func way(at index: Int) -> any MusicPlayer
    /// Its state by its surest signs, which judge its presses.
    func sureState() async -> PlayerState
    /// Whether AutoHush can mute it in place of a pause.
    func canBeMuted() async -> Bool
    /// Presses by `way`, checked as it allows (`checkable`: asked once per
    /// press, at the first way that doesn't check its own).
    func press(_ way: any MusicPlayer, to target: PlayerState, checkable: inout Bool?) async throws
}

extension BackupRouting {
    /// How long a play by the panel that failed keeps it out of the next
    /// plays (the engine's retries, a second apart): it shows on screen.
    static var panelPlayRest: TimeInterval { 10 }

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
    /// `covered`: false for a pause no mute will stand in for
    /// (`pauseUncovered`), which goes down the order at once.
    func pressByBackups(to target: PlayerState, covered: Bool = true) async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let call = pressCalls
        mutedTried = []
        // Looked at only when it changes the order.
        let state: CheckResult.WindowState? = wayOrder.dependsOnWindow(for: target) ? await windowState(pid) : nil
        let window = state.map { ", its window \($0.title)" } ?? ""
        var goesOn = target == .playing || !covered
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
                    logger.notice("\(self.name, privacy: .public): \(target == .playing ? "played" : "paused", privacy: .public) by its \(kind.logName, privacy: .public)\(index == 0 ? "" : " (a backup)", privacy: .public)\(window, privacy: .public)")
                }
                return
            } catch let notPressed as MediaKeyWay.NotPressed {
                // Not pressed: as one passed over; asked once in a pause.
                logger.notice("\(self.name, privacy: .public): its Play/Pause key isn’t pressed, \(notPressed.description, privacy: .public): the next way")
                pressed -= 1
                if target == .paused { mutedTried.insert(index) }
            } catch MusicPlayerError.stillLearning {
                logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) can’t press yet: the next way")
                learning = true
                pressed -= 1
            } catch MusicPlayerError.playerCommandFailed(.nothingToPlay) where target == .playing {
                // Refused on purpose (QuickTime Player plays only what it
                // paused): a backup would play what the user paused.
                logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) has nothing to play: no backup pressed")
                throw MusicPlayerError.playerCommandFailed(.nothingToPlay)
            } catch {
                logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) failed\(window, privacy: .public): \(error)")
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
    /// quiet ways first (round again once all were tried), then the
    /// Play/Pause key once in the pause, the panel last, once in the pause,
    /// while "the panel while muted" is on (the user, 2026-11-04). AutoHush
    /// asks again only while it's still muted and heard, so each retry is
    /// one press: a resume meanwhile isn't followed by a pause. A retry whose
    /// ways were all passed over (not allowed, the key not pressed, a page
    /// still learning) goes round the quiet ways once more, so it presses at
    /// least its own way.
    func pauseWhileMuted() async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let state: CheckResult.WindowState? = wayOrder.dependsOnWindow(for: .paused) ? await windowState(pid) : nil
        let order = wayOrder.order(in: state ?? .visible, for: .paused)
        let quiet = order.filter { ![.panel, .mediaKey].contains(wayOrder.ways[$0].kind) }
        let key = order.filter { wayOrder.ways[$0].kind == .mediaKey }
        let panel = panelWhileMuted ? order.filter { wayOrder.ways[$0].kind == .panel } : []
        // The quiet ways again, once each was tried; the key and the panel once.
        var startedOver = (quiet + key + panel).allSatisfy(mutedTried.contains)
        if startedOver { mutedTried.subtract(quiet) }
        while true {
            for index in quiet + key + panel where !mutedTried.contains(index) {
                mutedTried.insert(index)
                let kind = wayOrder.ways[index].kind
                guard let way = await allowedWay(index, kind: kind, pid: pid) else { continue }
                var checkable: Bool?
                do {
                    try await press(way, to: .paused, checkable: &checkable)
                    logger.notice("\(self.name, privacy: .public): paused by its \(kind.logName, privacy: .public)\(index == 0 ? "" : " (a backup)", privacy: .public) while muted")
                    return
                } catch let notPressed as MediaKeyWay.NotPressed {
                    logger.notice("\(self.name, privacy: .public): muted, its Play/Pause key isn’t pressed, \(notPressed.description, privacy: .public): the next way")
                } catch MusicPlayerError.stillLearning {
                    logger.notice("\(self.name, privacy: .public): muted, its \(kind.logName, privacy: .public) can’t press yet: the next way")
                } catch {
                    logger.notice("\(self.name, privacy: .public): muted, its \(kind.logName, privacy: .public) failed: \(error)")
                    throw error
                }
            }
            // Nothing pressed (each passed over): the quiet ways again, once,
            // so a retry presses at least its own way.
            guard !startedOver else { break }
            startedOver = true
            mutedTried.subtract(quiet)
        }
        throw MusicPlayerError.playerCommandFailed(.pressFailed)
    }

    /// The player of its way at `index` (its own at 0), unless it's a
    /// backup macOS would ask something for.
    private func allowedWay(_ index: Int, kind: WayOrder.Kind, pid: pid_t) async -> (any MusicPlayer)? {
        guard index != 0 else { return way(at: 0) }
        guard await backupAllowed(kind, pid) else {
            logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) isn’t allowed without macOS asking: passed over")
            return nil
        }
        return way(at: index)
    }
}
