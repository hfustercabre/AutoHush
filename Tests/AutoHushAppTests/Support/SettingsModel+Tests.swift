@testable import AutoHushApp
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
}
