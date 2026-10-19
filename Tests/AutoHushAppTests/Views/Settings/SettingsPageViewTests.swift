import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// Settings' pages no other test shows, drawn as their window draws them.
@Suite("Settings' pages, drawn")
@MainActor
struct SettingsPageViewTests {
    private let actions = FakeAppActions()

    @Test("About, Fades and Advanced draw", arguments: [SettingsWindowController.Page.about, .fades, .advanced])
    func page(_ page: SettingsWindowController.Page) {
        let updates = FakeUpdateCommands()
        updates.currentVersion = AppVersion("0.2.0")
        let model = SettingsModel.forTests(actions: actions, updates: updates)
        model.state.status.choosePlayer(named: "Jukebox")
        let navigation = SettingsNavigation()
        navigation.page = page
        let keys = SettingsKeys()
        let width = SettingsWindowController.initialSize.width - SettingsWindowController.sidebarWidth
        let size = drawn(SettingsPageView(model: model, navigation: navigation).environment(keys.page), width: width)
        #expect(size.height > 0)
    }
}
