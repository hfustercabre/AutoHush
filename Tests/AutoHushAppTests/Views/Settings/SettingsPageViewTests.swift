import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit

/// Settings' pages no other test shows, drawn as their window draws them.
@Suite("Settings' pages, drawn")
@MainActor
struct SettingsPageViewTests {
    private let actions = FakeAppActions()

    @Test("About, Fades, Advanced, Updates and Diagnostics draw, Diagnostics with every part unfolded",
          arguments: [SettingsWindowController.Page.about, .fades, .advanced, .updates, .diagnostics])
    func page(_ page: SettingsWindowController.Page) {
        let updates = FakeUpdateCommands()
        updates.currentVersion = AppVersion("0.2.0")
        let model = SettingsModel.forTests(actions: actions, updates: updates)
        model.state.status.choosePlayer(named: "Jukebox")
        #expect(model.foldedDiagnostics.isEmpty) // every part unfolded
        #expect(draws(page, model))
    }

    @Test("General draws the player's Reopen and Unmute, while it must be reopened and is muted for another app")
    func generalWithFixes() {
        let model = SettingsModel.forTests(actions: actions, updates: FakeUpdateCommands())
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.playerOptions[0].pausesByMuting = true
        model.state.status.setHealth(.ready)
        model.state.status.playerNeedsReopen = true
        model.state.status.playback = .pausedByMonitor
        #expect(model.offersReopenPlayer && model.offersUnmute)
        #expect(draws(.general, model))
    }

    /// `page` drawn as Settings' window draws it.
    private func draws(_ page: SettingsWindowController.Page, _ model: SettingsModel) -> Bool {
        let navigation = SettingsNavigation()
        navigation.page = page
        let keys = SettingsKeys()
        let width = SettingsWindowController.initialSize.width - SettingsWindowController.sidebarWidth
        let size = drawn(SettingsPageView(model: model, navigation: navigation).environment(keys.page), width: width)
        return size.height > 0
    }
}
