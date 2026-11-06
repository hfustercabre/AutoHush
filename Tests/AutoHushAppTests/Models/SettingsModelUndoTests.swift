import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// Settings' Undo and Redo of a card's Restore Defaults (U10a, the user's
/// pick, 2026-11-02): one step per press, putting back every setting it
/// changed (and only those), on the card's page.
@Suite("SettingsModel's Undo", .waitsTimeLimit)
@MainActor
struct SettingsModelUndoTests {
    /// What Settings asked of AppDelegate (the page Undo shows) and the updates.
    private let log = CallLog()
    private let actions: FakeAppActions
    private let updates: FakeUpdateCommands
    /// Where the user's settings and the menu bar icon's place are kept.
    private let store = InMemoryPreferenceStore()
    private let iconDefaults = MemoryDefaults()
    /// The Settings window's, a step only where a test closes one, as
    /// each press is an event of its own in the app.
    private let undo = UndoManager()
    private let model: SettingsModel

    init() {
        actions = FakeAppActions(log: log)
        updates = FakeUpdateCommands(log: log)
        updates.followsCommands = true
        undo.groupsByEvent = false
        model = SettingsModel(settings: UserSettings(preferences: Preferences(store: store)), updates: updates, actions: actions,
                              launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                              menuBarIcon: MenuBarIconPlace(defaults: iconDefaults))
        model.undoManager = undo
    }

    /// Everything a Restore Defaults could change: every preference kept,
    /// the menu bar icon's place, and the updates' choices. A setting
    /// restored outside what Undo keeps would differ after an Undo.
    private var everything: NSDictionary {
        var all = store.contents
        for (key, value) in iconDefaults.contents { all["menuBarIcon." + key] = value }
        all["updates"] = [updates.checksAutomatically, updates.mode.rawValue, updates.getsReleaseCandidates] as [Any]
        if let switches = model.chosenControls?.switches {
            all["backupSwitches"] = [switches.mainControl ?? "", switches.usesBackups, switches.panelWhileMuted] as [Any]
        }
        return all as NSDictionary
    }

    /// A press of the card's Restore Defaults: a step of its own.
    private func press(_ card: SettingsCard) {
        undo.beginUndoGrouping()
        model.restoreDefaults(card)
        undo.endUndoGrouping()
    }

    /// Every card's settings away from their defaults, and none greyed out
    /// but Fades' switch (on) and Modes' (off), which `card` changes too.
    private func changeEverything(for card: SettingsCard) {
        model.setTimings(TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                        fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: card != .fades,
                                        pausesOnOutputDisconnect: true, levelsMusic: true,
                                        levelingMaxCutDB: 14, levelingMinCutDB: 5,
                                        pausesForMicrophone: true, staysPausedAfterCalls: true, pausesForVoiceOver: false))
        if card == .modes { model.setDetectionMethod(.openStreams) }
        model.setKeepsMenuBarIconNearSystemIcons(true)
        updates.checksAutomatically = false
        updates.mode = .notify
        updates.getsReleaseCandidates = true
        // A chosen player with a panel among its backups, another main
        // control than its own chosen, both switches off.
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.chosenControls = .choosing(.menu, switches: BackupSwitches(usesBackups: false, panelWhileMuted: false,
                                                                                       mainControl: "menu"))
        actions.setsBackupSwitches = { [model] switches in
            model.state.status.chosenControls = model.chosenControls?.with(switches)
        }
    }

    @Test("Undo puts back every setting each card's Restore Defaults changed, on the card's page; Redo restores them again", arguments: SettingsCard.allCases)
    func undoRestoreDefaults(card: SettingsCard) {
        changeEverything(for: card)
        #expect(!model.isDefault(card))
        let changed = everything
        press(card)
        #expect(model.isDefault(card))
        let restored = everything
        #expect(restored != changed)
        #expect(undo.canUndo && undo.undoActionName == "Restore Defaults")

        log.calls = []
        undo.undo()
        #expect(everything == changed)
        #expect(!model.isDefault(card))
        #expect(log.calls.last == "\(card.page)") // Settings shows the card's page
        #expect(undo.canRedo && undo.redoActionName == "Restore Defaults")

        undo.redo()
        #expect(everything == restored && model.isDefault(card))
        #expect(log.calls.last == "\(card.page)")
        undo.undo()
        #expect(everything == changed)
    }

    @Test("each press is a step of its own: two cards restored take two Undos")
    func oneStepPerPress() {
        changeEverything(for: .timing)
        let changed = everything
        press(.timing)
        let timingRestored = everything
        press(.updates)
        #expect(model.isDefault(.timing) && model.isDefault(.updates))

        undo.undo()
        #expect(everything == timingRestored && !model.isDefault(.updates) && model.isDefault(.timing))
        #expect(log.calls.last == "about")
        undo.undo()
        #expect(everything == changed && !undo.canUndo)
        #expect(log.calls.last == "fineTuning")
    }

    @Test("the player controls' Undo puts back only the switch the restore changed, and only for the player they were the switches of")
    func backupSwitchesUndo() {
        changeEverything(for: .playerControls)
        model.actions?.setBackupSwitches(BackupSwitches(usesBackups: false, panelWhileMuted: true))
        press(.playerControls) // Use backup controls back on; the panel's was on, the main control its own
        model.actions?.setBackupSwitches(BackupSwitches(usesBackups: true, panelWhileMuted: false))
        undo.undo()
        #expect(model.chosenControls?.switches == BackupSwitches(usesBackups: false, panelWhileMuted: false))
        // Redone, then another player chosen: its switches stay as they are.
        undo.redo()
        model.state.status.choosePlayer(named: "Radio")
        model.actions?.setBackupSwitches(BackupSwitches(usesBackups: true, panelWhileMuted: true))
        log.calls = []
        undo.undo()
        #expect(model.chosenControls?.switches == BackupSwitches() && !log.calls.contains { $0.hasPrefix("backups") })
    }

    @Test("the player controls' Restore Defaults puts its own main control back, and Undo the one chosen, field by field: a switch turned since stays")
    func mainControlUndo() {
        changeEverything(for: .playerControls)
        model.actions?.setBackupSwitches(BackupSwitches(mainControl: "page")) // both switches on, its page the main control
        #expect(model.chosenControls?.main.kind == .page && !model.isDefault(.playerControls))
        press(.playerControls)
        #expect(model.chosenControls?.main.kind == .script && model.chosenControls?.switches == BackupSwitches())
        #expect(model.isDefault(.playerControls))
        model.actions?.setBackupSwitches(BackupSwitches(panelWhileMuted: false)) // turned since

        undo.undo()
        #expect(model.chosenControls?.main.kind == .page)
        #expect(model.chosenControls?.switches == BackupSwitches(panelWhileMuted: false, mainControl: "page"))
        undo.redo()
        #expect(model.chosenControls?.main.kind == .script)
        #expect(model.chosenControls?.switches == BackupSwitches(panelWhileMuted: false))
    }

    @Test("Undo and Redo put back only what the restore changed: a setting changed since, on the card or another, stays")
    func otherChangesStay() {
        changeEverything(for: .fades)
        press(.fades)
        // Changed since by controls that register no undo of their own: the
        // card's own page (a slider) and another card's (About's switch).
        var timings = model.timings
        timings.startConfirmation = 4
        model.setTimings(timings)
        updates.checksAutomatically = true

        undo.undo()
        #expect(!model.timings.fadesEnabled) // what the restore changed, put back
        #expect(model.timings.startConfirmation == 4 && updates.checksAutomatically)

        timings = model.timings
        timings.fadeOutDuration = 5
        model.setTimings(timings)
        updates.getsReleaseCandidates = false

        undo.redo()
        #expect(model.timings.fadesEnabled)
        #expect(model.timings.startConfirmation == 4 && model.timings.fadeOutDuration == 5)
        #expect(updates.checksAutomatically && !updates.getsReleaseCandidates)
    }

    @Test("without the Settings window's undo manager, Restore Defaults only restores")
    func noUndoManager() {
        model.undoManager = nil
        changeEverything(for: .pausing)
        model.restoreDefaults(.pausing)
        #expect(model.isDefault(.pausing) && !undo.canUndo)
    }

    @Test("each card's page is the one that shows it")
    func cardPages() {
        #expect(SettingsCard.allCases.map(\.page) == [.behavior, .behavior, .behavior, .behavior, .behavior,
                                                       .fineTuning, .fineTuning, .fineTuning, .fineTuning, .fineTuning, .general, .about])
        #expect(SettingsCard.playerControls.page == .fineTuning) // Media Player has a row to it
    }
}
