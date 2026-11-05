import Foundation
import AutoHushKit
import CheckedPlayers

// AddAppModel: what worked, and Use (or Mute It Instead).
extension AddAppModel {
    /// The ways that worked, in every window state or in some, that AutoHush
    /// can run, the recommended first (the setup's order): the user chooses
    /// one (U2, the user's pick, 2026-10-15). None: nothing it can use worked.
    var choosableWays: [CheckResult.WayKind] {
        workingWays.compactMap(\.kind).filter { !($0 == .panel && panelNeedsSound && antiDot) }
    }

    /// The ways that worked, in every window state or in some, that AutoHush
    /// can run, in the setup's order (the panel last): Use keeps the chosen
    /// one and the others as its backups, a panel only its sound tells in
    /// AntiDot mode too.
    private var workingWays: [PlayerSetup.Way] {
        guard let result, let setup = result.setup else { return [] }
        let worked = Set(result.ways.filter(\.worked).map(\.kind))
        return setup.ways.filter { $0.kind.map(worked.contains) == true }
    }

    /// The Now Playing panel worked, but its row doesn't follow the app: only
    /// its sound tells, which AntiDot mode doesn't hear, so it can't be chosen
    /// then, as muting can't (the user, 2026-10-16).
    var panelNeedsSound: Bool { result?.setup?.panelRowIsStale == true }

    /// Check Again is offered in the last step: with nothing to use (beside
    /// Mute It Instead), and beside Use when Now Playing was hidden in the
    /// menu bar, so its panel wasn't tried (the user, 2026-10-16), or when a
    /// way failed or wasn't checked with the app's windows closed.
    var offersCheckAgain: Bool {
        result != nil && (choosableWays.isEmpty || nowPlayingHidden || closedWaysMayWork)
    }

    /// The check found the app's windows closed, and a way didn't work or
    /// wasn't checked then: with a window open, it may (the 1.2.4 review's
    /// workflow note, the user's pick, 2026-10-29).
    var closedWaysMayWork: Bool {
        guard let result, result.windowsClosed else { return false }
        return result.ways.contains { $0.mark == .none || $0.mark == .noWindow }
    }

    /// The way Use makes AutoHush use: the user's choice, else the recommended.
    var chosenWay: CheckResult.WayKind? {
        pickedWay.flatMap { choosableWays.contains($0) ? $0 : nil } ?? choosableWays.first
    }

    /// The last step's backup switches (the user, 2026-11-05): as the user
    /// set them, else as the app kept them when it's checked again, else
    /// both on.
    var backupSwitches: BackupSwitches {
        get { pickedSwitches ?? chosen.flatMap { host?.backupSwitches(for: $0.bundleID) } ?? BackupSwitches() }
        set { pickedSwitches = newValue }
    }

    /// What would control the app with the chosen way, for the last step's
    /// switches: the chosen way, then the others that worked and the
    /// Play/Pause key, the panel last, as they're pressed.
    var backupControls: PlayerControls? {
        guard let result, let way = chosenWay, let main = result.ways.first(where: { $0.kind == way }) else { return nil }
        let others = workingWays.compactMap(\.kind).filter { $0 != way }
            .compactMap { kind in result.ways.first { $0.kind == kind } }
            .map { PlayerControls.Control(kind: WayOrder.Kind($0.kind), result: $0) }
        let key = PlayerControls.Control(kind: .mediaKey, result: nil)
        return PlayerControls(main: .init(kind: WayOrder.Kind(main.kind), result: main),
                              backups: others.filter { $0.kind != .panel } + [key] + others.filter { $0.kind == .panel },
                              switches: backupSwitches)
    }

    func choose(_ way: CheckResult.WayKind) {
        guard choosableWays.contains(way) else { return }
        pickedWay = way
    }

    /// Now Playing was hidden in the menu bar, so its panel wasn't tried:
    /// the last step offers to open where it's shown, then Check Again.
    var nowPlayingHidden: Bool { result?.ways.contains { $0.mark == .menuBarHidden } == true }

    func openMenuBarSettings() {
        presenter?.openMenuBarSettings()
    }

    /// The last step's Turn Off AntiDot Mode, when nothing that worked can be
    /// used in it: a way only the app's sound tells, or muting, then can.
    func turnOffAntiDot() {
        host?.turnOffAntiDot()
        antiDotChanges += 1
    }

    /// Muting needs Audio Recording, and isn't available in AntiDot mode
    /// (the last step's Mute It Instead).
    var canMute: Bool { permissions.audio == .allowed && !antiDot }

    /// The last step's Mute It Instead, when no way it can use worked: the
    /// app is muted while other apps play, never paused, and made the player.
    func useMuting() {
        guard let result, choosableWays.isEmpty, canMute, let app = chosen else { return }
        let setup = PlayerSetup(bundleID: app.bundleID, name: app.name, appURL: app.url, ways: [.mute])
        keptChecks.forget()
        host?.useCheckedApp(CheckResult(ways: result.ways, setup: setup), asksToReopen: reopenOutcome != .skipped)
        presenter?.closeWindow()
    }

    /// Asks for Audio Recording from the last step, for muting, and follows it.
    func allowMuting() {
        guard let app = chosen, let traits else { return }
        let current = permissions
        Task { [weak self] in
            await self?.host?.requestCheckPermission(.audioRecording, app: app, current: current)
            for _ in 0..<60 {
                guard let self, self.result != nil, !self.canMute else { return }
                await self.refreshPermissions(for: app, scriptable: traits.scriptable)
                await self.sleep(.seconds(1))
            }
        }
    }

    /// The last step's Use: keeps what worked and makes the app the player
    /// (asking to reopen it unless the user skipped that here). The chosen
    /// way is pressed; the others that worked are kept as its backups, with
    /// how each did in each window state (the user, 2026-11-04).
    func use() {
        guard let result, var setup = result.setup, let way = chosenWay else { return }
        let working = workingWays
        setup.ways = working.filter { $0.kind == way }
        setup.backups = working.filter { $0.kind != way }
        let kept = Set(working.compactMap(\.kind))
        setup.wayResults = result.ways.filter { kept.contains($0.kind) }
        setup.usesBackups = backupSwitches.usesBackups
        setup.panelWhileMuted = backupSwitches.panelWhileMuted
        keptChecks.forget()
        // The page's learned Play/Pause goes with the page, a backup's too:
        // without it, the app would wait to learn it and never pause (2026-10-18).
        host?.useCheckedApp(CheckResult(ways: result.ways, setup: setup, pageButton: kept.contains(.page) ? result.pageButton : nil),
                            asksToReopen: reopenOutcome != .skipped)
        presenter?.closeWindow()
    }
}
