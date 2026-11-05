import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// The player's own permission missing while its backup controls stand in
/// for it (the user, 2026-11-05): the menu warns with it, Settings' note
/// says it's still controlled.
@Suite("Backup controls standing in")
@MainActor
struct BackupsStandInTests {
    private let actions = FakeAppActions()

    private func model(automation: OSStatus) async -> SettingsModel {
        let center = PermissionCenter(system: .init(
            isTrusted: { true }, promptAccessibility: {}, automation: { _, _ in automation }, runningPID: { _ in 4242 },
            audio: { .granted }, requestAudio: { _ in }, openPane: { _ in }
        ))
        let player = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        await center.refresh(chosenPlayer: { player }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false)
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: center, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                                  menuBarIcon: MenuBarIconPlace(defaults: MemoryDefaults()))
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.setHealth(.ready)
        model.state.status.chosenControls = .choosing()
        return model
    }

    @Test("its own permission missing while it's controlled by its backups: the menu's warning, under the card, and Settings' note")
    func standsIn() async {
        let model = await model(automation: OSStatus(errAEEventNotPermitted))
        let permission = Permission.automation(player: "Jukebox")
        #expect(model.backupsStandIn == permission)
        let menu = StatusMenuModel(status: model.state.status)
        menu.settings = model
        #expect(menu.sections.prefix(2) == [.card, .backupsStandIn(permission)])
        #expect(ControlPermissionNote.standInNote(permission, player: "Jukebox")
                == "Without Automation access, AutoHush controls Jukebox by its backup controls.")
    }

    @Test("no warning while it's allowed, while it can't be controlled at all (the card asks), with its backups off, or with another main control chosen")
    func doesNotStandIn() async {
        #expect(await model(automation: noErr).backupsStandIn == nil)
        let denied = { await self.model(automation: OSStatus(errAEEventNotPermitted)) }
        let notControlled = await denied()
        notControlled.state.status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        #expect(notControlled.backupsStandIn == nil)
        let backupsOff = await denied()
        backupsOff.state.status.chosenControls = .choosing(switches: BackupSwitches(usesBackups: false))
        #expect(backupsOff.backupsStandIn == nil)
        let otherMain = await denied()
        otherMain.state.status.chosenControls = .choosing(.menu, switches: BackupSwitches(mainControl: "menu"))
        #expect(otherMain.backupsStandIn == nil)
    }
}
