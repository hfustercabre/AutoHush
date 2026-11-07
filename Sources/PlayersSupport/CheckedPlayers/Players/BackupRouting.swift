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
    /// Whether a way may be pressed without macOS asking anything: a
    /// backup, or its own while its permission is missing (`ownWayDenied`).
    var backupAllowed: @Sendable (WayOrder.Kind, pid_t) async -> Bool { get }
    /// Its own way's permission is missing (Automation, Accessibility) while
    /// a backup can be pressed: why, and its own way passed over at each
    /// press until macOS allows it again (the user, 2026-11-05); `nil`
    /// otherwise.
    var ownWayDenied: MusicPlayerError? { get set }
    /// Its state can be told without its own way (an added app's Now
    /// Playing report); else a backup that tells it (its menu, its page, a
    /// script) must be allowed for its own way to be passed over.
    var statesWithoutOwnWay: Bool { get }
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
    /// Which control paused and played it last (`PlayerControls`).
    var lastUsed: OSAllocatedUnfairLock<LastControls> { get }
    /// The place in `wayOrder` of its main control: its own (0) unless the
    /// user chose another in Settings (`WayOrder.mainIndex(for:)`), read at
    /// each press.
    var mainIndex: Int { get }
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
    /// A press by its own way alone, with its backups off: a pause or a
    /// play begun all the same, so one going down its backups (begun
    /// before they were turned off) stops, and a muted pause starts its
    /// tries again (`mutedTried`).
    func ownPressBegins() {
        pressCalls += 1
        mutedTried = []
    }

    /// Whether `error`, its own way's from `verifyControlAccess`, leaves it
    /// to its backups: a missing permission (Automation, Accessibility)
    /// while its backups are in use (`usesBackups`) and one of them can be
    /// pressed without macOS asking (`backupAllowed`), and its state can
    /// still be told: by a backup that tells it (its menu, its page, a
    /// script), allowed too, or without them (`statesWithoutOwnWay`); else
    /// it would never be paused, which says nothing. Its own way is then
    /// passed over at each press until macOS allows it (`ownWayDenied`);
    /// false otherwise, as before (the user, 2026-11-05).
    func passesOverOwnWay(after error: any Error, usesBackups: Bool) async -> Bool {
        guard let denied = error as? MusicPlayerError, denied == .automationPermissionDenied || denied == .accessibilityPermissionDenied,
              usesBackups, let wayOrder, let pid = processIdentifier() else {
            ownWayDenied = nil
            return false
        }
        var pressable = false, tellsState = statesWithoutOwnWay
        for way in wayOrder.ways.dropFirst() where await backupAllowed(way.kind, pid) {
            pressable = true
            if [.menu, .page, .script].contains(way.kind) { tellsState = true }
        }
        if pressable, tellsState {
            if ownWayDenied == nil {
                logger.notice("\(self.name, privacy: .public): its \(wayOrder.ways[0].kind.logName, privacy: .public) isn’t allowed (\(denied)): controlled by its backups")
            }
            ownWayDenied = denied
            return true
        }
        ownWayDenied = nil
        return false
    }

    /// Its access, as its presses need it: with another main control chosen
    /// and its backups off (pressed alone), that one's, asked of macOS
    /// without a prompt (`backupAllowed`), its own way not pressed; missing,
    /// the permission it needs. Otherwise its own way's (`verifyOwn`), its
    /// backups standing in for a missing permission (`passesOverOwnWay`).
    func verifyAccess(usesBackups: Bool, verifyOwn: () async throws -> Void) async throws {
        if let wayOrder, mainIndex != 0, !usesBackups {
            guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
            let kind = wayOrder.ways[mainIndex].kind
            guard await backupAllowed(kind, pid) else {
                throw kind == .script ? MusicPlayerError.automationPermissionDenied : MusicPlayerError.accessibilityPermissionDenied
            }
            ownWayDenied = nil
            return
        }
        do {
            try await verifyOwn()
            ownWayAllowed()
        } catch {
            guard await passesOverOwnWay(after: error, usesBackups: usesBackups) else { throw error }
        }
    }

    /// Its own way's access checked and allowed: pressed again.
    func ownWayAllowed() {
        guard ownWayDenied != nil else { return }
        ownWayDenied = nil
        logger.notice("\(self.name, privacy: .public): its own way is allowed again")
    }

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
    /// (Automation, Accessibility) is passed over, as its own way is while
    /// its permission is missing (`ownWayDenied`), and a way that can't
    /// press yet (its page's button not learned) hands on to the next. A
    /// failure throws the first way's error; nothing pressed at all, its
    /// own way's missing permission.
    /// `covered`: false for a pause no mute will stand in for
    /// (`pauseUncovered`), which goes down the order at once. `alone`: its
    /// backups off while another main control was chosen: that one only.
    func pressByBackups(to target: PlayerState, covered: Bool = true, alone: Bool = false) async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let call = pressCalls
        mutedTried = []
        let main = mainIndex
        // Looked at only when it changes the order; when its first way is
        // the same in every state, only once that one failed or was passed
        // over (the common pause and play wait for no look).
        let dependsOnWindow = !alone && wayOrder.dependsOnWindow(for: target, main: main)
        let firstAnyway = dependsOnWindow ? wayOrder.firstInEveryState(for: target, main: main) : nil
        var state: CheckResult.WindowState? = dependsOnWindow && firstAnyway == nil ? await windowState(pid) : nil
        var goesOn = target == .playing || !covered
        if !goesOn { goesOn = await !canBeMuted() }
        var firstError: (any Error)?
        var pressed = 0, learning = false
        var checkable: Bool?
        var order = alone ? [main] : firstAnyway.map { [$0] } ?? wayOrder.order(in: state ?? .visible, for: target, main: main)
        var next = 0
        while true {
            if next == order.count, firstAnyway != nil, state == nil {
                if pressed > 0, !goesOn || pressCalls != call { break }
                let looked = await windowState(pid)
                state = looked
                order += wayOrder.order(in: looked, for: target, main: main).filter { !order.contains($0) }
            }
            guard next < order.count else { break }
            let index = order[next]
            next += 1
            let window = state.map { ", its window \($0.title)" } ?? ""
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
                lastUsed.withLock { $0.note(kind, for: target) }
                if index != 0 || state != nil {
                    logger.notice("\(self.name, privacy: .public): \(target == .playing ? "played" : "paused", privacy: .public) by its \(kind.logName, privacy: .public)\(index == main ? "" : " (a backup)", privacy: .public)\(window, privacy: .public)")
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
        throw firstError ?? (learning ? MusicPlayerError.stillLearning : ownWayDenied ?? MusicPlayerError.playerCommandFailed(.pressFailed))
    }

    /// Muted in place of its pause, and still heard: one way, the next in
    /// the order for the window's state not yet tried in this pause, the
    /// quiet ways first (round again once all were tried), then the
    /// Play/Pause key once in the pause, the panel last, once in the pause,
    /// while "the panel while muted" is on (the user, 2026-11-04), or
    /// always when it's the main control, which has no such switch (the
    /// user, 2026-11-05). AutoHush
    /// asks again only while it's still muted and heard, so each retry is
    /// one press: a resume meanwhile isn't followed by a pause. A retry whose
    /// ways were all passed over (not allowed, the key not pressed, a page
    /// still learning) goes round the quiet ways once more, so it presses at
    /// least its own way.
    /// `alone`: its backups off while another main control was chosen:
    /// that one only.
    func pauseWhileMuted(alone: Bool = false) async throws {
        guard let wayOrder, let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        pressCalls += 1
        let main = mainIndex
        let state: CheckResult.WindowState? = !alone && wayOrder.dependsOnWindow(for: .paused, main: main) ? await windowState(pid) : nil
        let order = alone ? [main] : wayOrder.order(in: state ?? .visible, for: .paused, main: main)
        let quiet = order.filter { ![.panel, .mediaKey].contains(wayOrder.ways[$0].kind) }
        let key = order.filter { wayOrder.ways[$0].kind == .mediaKey }
        let panel = order.filter { wayOrder.ways[$0].kind == .panel && (panelWhileMuted || $0 == main) }
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
                    lastUsed.withLock { $0.note(kind, for: .paused) }
                    logger.notice("\(self.name, privacy: .public): paused by its \(kind.logName, privacy: .public)\(index == main ? "" : " (a backup)", privacy: .public) while muted")
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
        throw ownWayDenied ?? MusicPlayerError.playerCommandFailed(.pressFailed)
    }

    /// The player of its way at `index` (its own at 0), unless it's a
    /// backup macOS would ask something for, or its own while its
    /// permission is missing (`ownWayDenied`, checked again without asking:
    /// allowed now, it's pressed again).
    private func allowedWay(_ index: Int, kind: WayOrder.Kind, pid: pid_t) async -> (any MusicPlayer)? {
        if index == 0 {
            guard let denied = ownWayDenied else { return way(at: 0) }
            guard await backupAllowed(kind, pid) else {
                logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) isn’t allowed (\(denied)): passed over")
                return nil
            }
            ownWayAllowed()
            return way(at: 0)
        }
        guard await backupAllowed(kind, pid) else {
            logger.notice("\(self.name, privacy: .public): its \(kind.logName, privacy: .public) isn’t allowed without macOS asking: passed over")
            return nil
        }
        return way(at: index)
    }
}
