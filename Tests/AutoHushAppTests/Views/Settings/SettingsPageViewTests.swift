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

    @Test("About (with Updates), Behavior, Fine-Tuning, Media Player and Diagnostics draw, Diagnostics with every part unfolded",
          arguments: [SettingsWindowController.Page.about, .behavior, .fineTuning, .mediaPlayer, .diagnostics])
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

    @Test("General draws a web app's controls, learned or not, with the button that learns them", arguments: [
        LearningStatus.learned, .learning(hasPlayed: false),
    ])
    func generalWithControls(_ learning: LearningStatus) {
        let model = SettingsModel.forTests(actions: actions, updates: FakeUpdateCommands())
        model.state.status.choosePlayer(named: "YT Music")
        model.state.status.learning = learning
        #expect(model.canLearnControlsAgain)
        #expect(draws(.general, model))
    }

    @Test("Diagnostics draws every part unfolded: how AutoHush is doing, the apps with sound or none, each section's rows with their marks and fixes",
          arguments: [DiagnosticsSnapshot.Overview.Kind.working, .attention, .off, .starting])
    func diagnosticsUnfolded(_ kind: DiagnosticsSnapshot.Overview.Kind) {
        let model = SettingsModel.forTests(actions: actions, updates: FakeUpdateCommands())
        model.state.status.choosePlayer(named: "Jukebox")
        model.diagnostics = Self.diagnostics(kind, apps: kind != .starting) // starting: none has sound yet
        #expect(model.foldedDiagnostics.isEmpty)
        #expect(draws(.diagnostics, model, height: 2400)) // every row in sight
    }

    /// Diagnostics as AutoHush finds it, each section with a row of every
    /// mark and each fix.
    private static func diagnostics(_ kind: DiagnosticsSnapshot.Overview.Kind, apps: Bool) -> DiagnosticsSnapshot {
        typealias Row = DiagnosticsSnapshot.Row
        let rows = [
            Row(label: "Player", value: "Jukebox 2.1", mark: .ok),
            Row(label: "Automation for Jukebox", value: "Not allowed", mark: .problem, fix: .allow(.automation(player: "Jukebox"))),
            Row(label: "Controls", value: "Not learned", mark: .problem, fix: .learnControls),
            Row(label: "Media player", value: "None chosen", mark: .neutral, fix: .choosePlayer),
            Row(label: "Version", value: "0.2.0 (2)"),
        ]
        let kinds: [DiagnosticsSnapshot.Section.Kind] = [.player, .behavior, .detection, .permissions, .autoHush, .mac]
        return DiagnosticsSnapshot(
            overview: .init(kind: kind, title: "Working normally", detail: "Jukebox · Paused — Google Chrome is playing"),
            apps: apps ? [.init(id: "com.google.Chrome", name: "Google Chrome", bundlePath: nil, judgement: "Playing", evidence: "-20 dBFS"),
                          .init(id: "org.videolan.vlc", name: "VLC", bundlePath: nil, judgement: "Silent, ignored", evidence: nil)] : [],
            appsSummary: apps ? "Google Chrome, VLC" : "None",
            sections: kinds.map { .init(kind: $0, title: "\($0)", summary: "Summary", rows: rows) },
            text: "The report"
        )
    }

    /// `page` drawn as Settings' window draws it.
    private func draws(_ page: SettingsWindowController.Page, _ model: SettingsModel, height: CGFloat = 600) -> Bool {
        let navigation = SettingsNavigation()
        navigation.page = page
        let keys = SettingsKeys()
        let width = SettingsWindowController.initialSize.width - SettingsWindowController.sidebarWidth
        let size = drawn(SettingsPageView(model: model, navigation: navigation).environment(keys.page), width: width, height: height)
        return size.height > 0
    }
}
