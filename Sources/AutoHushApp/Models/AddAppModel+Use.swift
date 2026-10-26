import Foundation
import CheckedPlayers

// AddAppModel: what worked, and Use (or Mute It Instead).
extension AddAppModel {
    /// The ways that worked, in every window state or in some, that AutoHush
    /// can run, the recommended first (the setup's order): the user chooses
    /// one (U2, the user's pick, 2026-10-15). None: nothing it can use worked.
    var choosableWays: [CheckResult.WayKind] {
        guard let result, let setup = result.setup else { return [] }
        let worked = Set(result.ways.filter(\.worked).map(\.kind))
        return setup.ways.compactMap(\.kind).filter { worked.contains($0) && !($0 == .panel && panelNeedsSound && antiDot) }
    }

    /// The Now Playing panel worked, but its row doesn't follow the app: only
    /// its sound tells, which AntiDot mode doesn't hear, so it can't be chosen
    /// then, as muting can't (the user, 2026-10-16).
    var panelNeedsSound: Bool { result?.setup?.panelRowIsStale == true }

    /// Check Again is offered in the last step: with nothing to use (beside
    /// Mute It Instead), and beside Use when Now Playing was hidden in the
    /// menu bar, so its panel wasn't tried (the user, 2026-10-16).
    var offersCheckAgain: Bool {
        guard let result else { return false }
        return choosableWays.isEmpty || result.ways.contains { $0.mark == .menuBarHidden }
    }

    /// The way Use makes AutoHush use: the user's choice, else the recommended.
    var chosenWay: CheckResult.WayKind? {
        pickedWay.flatMap { choosableWays.contains($0) ? $0 : nil } ?? choosableWays.first
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
                self.permissions = await self.readPermissions(app, scriptable: traits.scriptable)
                await self.sleep(.seconds(1))
            }
        }
    }

    /// The last step's Use: keeps what worked and makes the app the player
    /// (asking to reopen it unless the user skipped that here).
    func use() {
        guard let result, var setup = result.setup, let way = chosenWay else { return }
        // Only the chosen way: the others as its backup are parked (the user, 2026-10-15).
        setup.ways = setup.ways.filter { $0.kind == way }
        keptChecks.forget()
        // The page's learned Play/Pause goes with the page: without it, the
        // app would wait to learn it and never pause (2026-10-18).
        host?.useCheckedApp(CheckResult(ways: result.ways, setup: setup, pageButton: way == .page ? result.pageButton : nil),
                            asksToReopen: reopenOutcome != .skipped)
        presenter?.closeWindow()
    }
}
