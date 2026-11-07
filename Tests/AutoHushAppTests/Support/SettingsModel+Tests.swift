import Foundation
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension SettingsModel {
    /// A model on settings in memory, with launch at login off and the menu
    /// bar icon's place kept in memory too, that asks
    /// `actions` and `updates` what Settings asks of AppDelegate and the
    /// updates. It holds `actions` weakly: the test keeps them.
    static func forTests(actions: FakeAppActions, updates: FakeUpdateCommands = FakeUpdateCommands(),
                         settings: UserSettings = .inMemory()) -> SettingsModel {
        SettingsModel(settings: settings, updates: updates, actions: actions,
                      launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                      menuBarIcon: MenuBarIconPlace(defaults: MemoryDefaults()))
    }

    /// The Jukebox player chosen and ready, its controls as `choosing()`
    /// gives them, macOS answering `automation` for its own way: its
    /// Automation denied (`errAEEventNotPermitted`), its backup controls
    /// stand in for it (`backupsStandIn`).
    static func withAutomation(_ automation: OSStatus, actions: FakeAppActions) async -> SettingsModel {
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
}
