import Foundation
import Testing
@testable import CheckedPlayers
@testable import WebAppPlayers
@testable import AutoHushKit
import PlayersTestSupport

@Suite("PlayerControls")
struct PlayerControlsTests {
    private static let app = URL(fileURLWithPath: "/Applications/Jukebox.app")

    private func setup(results: Bool) -> PlayerSetup {
        PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: Self.app, ways: [.menu(menuName: "Controls")],
                    backups: [.page(.webKit), .panel(rememberedRow: nil)],
                    wayResults: results ? [.init(kind: .menu, mark: .works), .init(kind: .page, mark: .some, failedStates: [.hidden]),
                                           .init(kind: .panel, mark: .works)] : [],
                    usesBackups: true, panelWhileMuted: false)
    }

    @Test("an added app's controls: its chosen way, then its backups as they're pressed, the Play/Pause key before the panel, each with how its check found it, and its switches")
    func addedApp() {
        let controls = CheckedPlayer(setup: setup(results: true), reports: nil, store: MemorySetupStore()).controls
        #expect(controls.main == .init(kind: .menu, result: .init(kind: .menu, mark: .works)))
        #expect(controls.backups.map(\.kind) == [.page, .mediaKey, .panel])
        #expect(controls.backups[0].found?.failedStates == [.hidden] && controls.backups[1].found == nil)
        #expect(controls.switches == BackupSwitches(usesBackups: true, panelWhileMuted: false) && !controls.needsCheckAgain)
        #expect(controls.hasPanelBackup && controls.backupsInUse)
    }

    @Test("a control that will be choosable once learned is listed among the choices, in its place, but isn't one")
    func notYetChoices() {
        let all: [PlayerControls.Control] = [CheckResult.WayKind.script, .menu, .page].map {
            PlayerControls.Control(kind: WayOrder.Kind($0), result: CheckResult.WayResult(kind: $0, mark: .works))
        } + [PlayerControls.Control(kind: .mediaKey, result: nil),
             PlayerControls.Control(kind: .panel, result: CheckResult.WayResult(kind: .panel, mark: .works))]
        let controls = PlayerControls(all: all, chosen: nil, choosable: { control, _ in control.kind != .page && control.kind != .mediaKey }, switches: BackupSwitches(),
                                      notYet: { control, _ in control.kind == .page })
        #expect(controls.choices.map(\.kind) == [.script, .menu, .panel])
        #expect(controls.notYetChoices.map(\.kind) == [.page])
        let listed: [WayOrder.Kind] = controls.listedChoices.map(\.kind)
        #expect(listed == [.script, .menu, .page, .panel])
    }

    @Test("the panel's switch shows only while the panel is a backup, not its main control")
    func panelSwitch() {
        let panel = PlayerControls.Control(kind: .panel, result: nil), menu = PlayerControls.Control(kind: .menu, result: nil)
        let key = PlayerControls.Control(kind: .mediaKey, result: nil)
        let main = PlayerControls(main: panel, backups: [key, menu], switches: BackupSwitches())
        #expect(!main.hasPanelBackup && main.hasPanel)
        let backup = PlayerControls(main: menu, backups: [key, panel], switches: BackupSwitches())
        #expect(backup.hasPanelBackup && backup.hasPanel)
        let none = PlayerControls(main: menu, backups: [key], switches: BackupSwitches())
        #expect(!none.hasPanelBackup && !none.hasPanel)
    }

    @Test("an app added before backups were kept has no Play/Pause key and needs a new check")
    func olderApp() {
        let controls = CheckedPlayer(setup: setup(results: false), reports: nil, store: MemorySetupStore()).controls
        #expect(controls.backups.map(\.kind) == [.page, .panel] && controls.needsCheckAgain && !controls.backupsInUse)
    }

    @Test("Settings sets an added app's switches in its setup and its player, the same one (a pause AutoHush holds stays); one checked before backups has none to keep")
    func settingSwitches() {
        let store = MemorySetupStore()
        store.save(setup(results: true))
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        let first = players.current().first
        #expect(players.switches(for: "com.example.jukebox") == BackupSwitches(usesBackups: true, panelWhileMuted: false))
        players.setSwitches(BackupSwitches(usesBackups: false, panelWhileMuted: true), for: "com.example.jukebox")
        #expect(store.setups().first?.usesBackups == false && store.setups().first?.panelWhileMuted == true)
        #expect(players.current().first === first)
        #expect((first as? CheckedPlayer)?.controls.switches == BackupSwitches(usesBackups: false, panelWhileMuted: true))
        // Changed in the setup some other way (a check kept again): a new player.
        store.update("com.example.jukebox") { $0.usesBackups = true }
        #expect(players.current().first !== first)
        store.save(setup(results: false))
        #expect(players.switches(for: "com.example.jukebox") == nil)
    }

    @Test("the switches reach the player in use too, when it's no longer the one kept (its setup changed since it was made)")
    func switchesReachPlayerInUse() {
        let store = MemorySetupStore()
        store.save(setup(results: true))
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        let inUse = players.current().first
        store.update("com.example.jukebox") { $0.name = "Jukebox 2" } // as a saved panel row would
        let kept = players.current().first
        #expect(kept !== inUse)
        players.setSwitches(BackupSwitches(usesBackups: false), for: "com.example.jukebox", player: inUse)
        #expect((inUse as? CheckedPlayer)?.controls.switches.usesBackups == false)
        #expect((kept as? CheckedPlayer)?.controls.switches.usesBackups == false)
    }
}
