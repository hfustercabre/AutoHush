import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// Settings' pages no other test shows, drawn as their window draws them.
@Suite("Settings' pages, drawn", .waitsTimeLimit)
@MainActor
struct SettingsPageViewTests {
    private let actions = FakeAppActions()

    @Test("About (with Updates), Behavior, Fine-Tuning, Media Player and Diagnostics draw, Diagnostics with every part unfolded",
          arguments: [SettingsPage.about, .behavior, .fineTuning, .mediaPlayer, .diagnostics])
    func page(_ page: SettingsPage) {
        let updates = FakeUpdateCommands()
        updates.currentVersion = AppVersion("0.2.0")
        let model = SettingsModel.forTests(actions: actions, updates: updates)
        model.state.status.choosePlayer(named: "Jukebox")
        #expect(model.foldedDiagnostics.isEmpty) // every part unfolded
        #expect(draws(page, model))
    }

    @Test("About draws its compact header, the icon beside the name and the version, in a window too short for the stacked one, and keeps it there")
    func aboutCompactHeader() throws {
        // A fit put compact by a page too short at 64 pt, its way back measured (AboutFitTests' numbers).
        var compact = AboutFit()
        compact.pageChanged(to: CGSize(width: 640, height: 480))
        compact.contentMeasured(height: 520)
        compact.nameMeasured(CGSize(width: 80, height: 20))
        compact.contentMeasured(height: 440)
        try #require(compact.isCompact && compact.stackedExtra > 0)
        let last = AboutSettingsView.lastFit
        defer { AboutSettingsView.lastFit = last }
        AboutSettingsView.lastFit = compact // the opening resumes it
        let updates = FakeUpdateCommands()
        updates.currentVersion = AppVersion("0.2.0")
        let model = SettingsModel.forTests(actions: actions, updates: updates)
        #expect(draws(.about, model, height: 300))
        #expect(AboutSettingsView.lastFit?.isCompact == true)
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

    @Test("General draws Try Again after a given-up resume, as the menu's card has it")
    func generalTryAgainAfterGivenUpResume() {
        let model = SettingsModel.forTests(actions: actions, updates: FakeUpdateCommands())
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.setHealth(.ready)
        model.state.status.resumeError = ControlError(MusicPlayerError.playerNotResponding, player: "Jukebox")
        #expect(model.showsResumeFailure)
        let givenUp = drawn(pageView(.general, model), width: Self.pageWidth).height
        model.state.status.resumeError = nil
        let button = drawn(PlayerFixButtons.tryAgain(inCard: false) {}, width: Self.pageWidth).height
        let plain = drawn(pageView(.general, model), width: Self.pageWidth).height
        // Taller by the button's row at least.
        #expect(givenUp >= plain + button, "\(givenUp) given up, \(plain) without, the button \(button)")
    }

    @Test("General draws a web app's controls, learned or not, with the button that learns them", arguments: [
        LearningStatus.learned, .learning(hasPlayed: false),
    ])
    func generalWithControls(_ learning: LearningStatus) {
        let model = SettingsModel.forTests(actions: actions, updates: FakeUpdateCommands())
        model.state.status.choosePlayer(named: "Yodel Music")
        model.state.status.learning = learning
        #expect(model.canLearnControlsAgain)
        #expect(draws(.general, model))
    }

    @Test("General and Media Player show what the chosen player lacks, with its button, and drop it once it's allowed (U7a)",
          arguments: [SettingsPage.general, .mediaPlayer])
    func missingControl(_ page: SettingsPage) async {
        let status = Locked(OSStatus(errAEEventNotPermitted))
        let center = PermissionCenter(system: .init(
            isTrusted: { true },
            promptAccessibility: {},
            automation: { _, _ in status.value },
            runningPID: { _ in 4242 },
            audio: { .granted },
            requestAudio: { _ in },
            openPane: { _ in }
        ))
        let player = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox")
        let refresh = { await center.refresh(chosenPlayer: { player }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: false) }
        await refresh()
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: center, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                                  menuBarIcon: MenuBarIconPlace(defaults: MemoryDefaults()))
        model.state.status.choosePlayer(named: "Jukebox")
        #expect(model.permissions.controlAccess == .denied)
        let missing = drawn(pageView(page, model), width: Self.pageWidth).height
        status.value = noErr
        await refresh()
        #expect(model.permissions.controlAccess == .allowed)
        let allowed = drawn(pageView(page, model), width: Self.pageWidth).height
        let note = drawn(NoteLabel("AutoHush can’t control Jukebox without Automation access."), width: Self.pageWidth).height
        // Taller by the note at least, with the button under it.
        #expect(missing >= allowed + note, "\(missing) missing, \(allowed) allowed, the note \(note)")
    }

    @Test("Behavior, Fine-Tuning, General and About draw with every card changed, each with its Restore Defaults; Behavior and Fine-Tuning in AntiDot mode too", arguments: [
        (SettingsPage.behavior, false), (.behavior, true), (.fineTuning, false), (.fineTuning, true), (.general, false),
        (.about, false),
    ])
    func everyCardChanged(_ page: SettingsPage, _ antiDot: Bool) {
        let updates = FakeUpdateCommands()
        let model = SettingsModel.forTests(actions: actions, updates: updates)
        model.state.status.choosePlayer(named: "Jukebox")
        // Every card of the page changed, so each draws its Restore Defaults
        // (B4, the full check, 2026-10-27: none was drawn); Volume's and
        // Volume Limits' only out of AntiDot mode, Modes' only in it.
        model.setTimings(TimingSettings(startConfirmation: 2, silenceThresholdDB: -40, fadeOutDuration: 3,
                                        fadesEnabled: page != .behavior, pausesOnOutputDisconnect: true, levelsMusic: true,
                                        levelingMaxCutDB: 14, staysPausedAfterCalls: true))
        if antiDot {
            model.setAntiDotMode(true)
            model.setDetectionMethod(.openStreams)
        }
        let cards: [SettingsCard] = switch page {
        case .behavior: [.pausing, .resuming, .fades, antiDot ? .modes : .volume]
        case .fineTuning: [.playerControls, .timing, .fadeLengths, .detection] + (antiDot ? [] : [.volumeLimits])
        case .general: [.startup]
        default: [.updates]
        }
        if page == .general { model.setKeepsMenuBarIconNearSystemIcons(true) }
        // Another main control chosen, the backups off.
        model.state.status.chosenControls = .choosing(.page, switches: BackupSwitches(usesBackups: false, mainControl: "page"))
        updates.checksAutomatically = false
        updates.mode = .notify
        for card in cards { #expect(!model.isDefault(card), "\(card)") }
        #expect(draws(page, model))
    }

    @Test("Fine-Tuning draws the player's controls first: the main control's pop-up with its note, or its one control; an app to check again, a web app not learned", arguments: [
        PlayerControls.choosing(), .choosing(.page, switches: BackupSwitches(mainControl: "page")),
        .choosing(.panel, switches: BackupSwitches(usesBackups: false, mainControl: "panel")),
        PlayerControls(main: .init(kind: .menu, result: .init(kind: .menu, mark: .works)), backups: [.init(kind: .mediaKey, result: nil)],
                       switches: BackupSwitches()),
        .choosing(needsCheckAgain: true),
        PlayerControls(main: .init(kind: .page, result: nil), backups: [.init(kind: .panel, result: nil)], switches: BackupSwitches(),
                       notLearned: true),
    ])
    func fineTuningControls(_ controls: PlayerControls) {
        let model = SettingsModel.forTests(actions: actions)
        model.state.status.choosePlayer(named: "Jukebox")
        let without = drawn(pageView(.fineTuning, model), width: Self.pageWidth).height
        model.state.status.chosenControls = controls
        let with = drawn(pageView(.fineTuning, model), width: Self.pageWidth).height
        let row = drawn(SwitchRow(Text(verbatim: BackupText.uses), isOn: .constant(true)), width: Self.pageWidth).height
        // Taller by the card's rows at least: its main control and the switch.
        #expect(with >= without + 2 * row, "\(with) with the card, \(without) without, a row \(row)")
    }

    @Test("Media Player draws a card of the player's name with its Controls row to Fine-Tuning, while Fine-Tuning has its card; none without")
    func mediaPlayerControlsRow() {
        let model = SettingsModel.forTests(actions: actions)
        model.state.status.choosePlayer(named: "Jukebox")
        let without = drawn(pageView(.mediaPlayer, model), width: Self.pageWidth).height
        model.state.status.chosenControls = .choosing()
        let with = drawn(pageView(.mediaPlayer, model), width: Self.pageWidth).height
        let row = drawn(FineTuningRow(model: model, card: .playerControls, title: BackupText.controls,
                                      value: BackupText.summary(.choosing())), width: Self.pageWidth).height
        #expect(with >= without + row, "\(with) with the row, \(without) without, the row \(row)")
        // The row opens Fine-Tuning at the card.
        model.showFineTuning(.playerControls)
        #expect(model.fineTuningFocus == .playerControls && actions.log.calls.last == "fineTuning")
    }

    @Test("Behavior draws Modes' notes: Audio Recording missing, with Allow and Use AntiDot Mode, or allowed and waiting for AutoHush to reopen, AntiDot mode unavailable for the player",
          arguments: [false, true])
    func modesNotes(_ unavailable: Bool) async {
        let center = PermissionCenter(system: .init(
            isTrusted: { true },
            promptAccessibility: {},
            automation: { _, _ in noErr },
            runningPID: { _ in 4242 },
            audio: { .denied },
            requestAudio: { _ in },
            openPane: { _ in }
        ))
        await center.refresh(chosenPlayer: { nil }, detectionMethod: .audioLevels, detection: .audioLevel, awaitsReopen: unavailable)
        let model = SettingsModel(settings: .inMemory(), updates: FakeUpdateCommands(), permissionCenter: center, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Jukebox")
        // A player only its sound tells: AntiDot mode can't be turned on with it.
        model.state.status.playerOptions[0].pausesByMuting = unavailable
        model.state.status.playerOptions[0].needsAudioLevels = unavailable
        #expect(!model.isAntiDotMode && !model.permissions.audio.isSatisfied)
        #expect(model.permissions.audio == (unavailable ? .needsReopen : .denied) && (model.antiDotUnavailableFor != nil) == unavailable)
        #expect(draws(.behavior, model))
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
                          .init(id: "org.example.viewer", name: "Viewer", bundlePath: nil, judgement: "Silent, ignored", evidence: nil)] : [],
            appsSummary: apps ? "Google Chrome, Viewer" : "None",
            sections: kinds.map { .init(kind: $0, title: "\($0)", summary: "Summary", rows: rows) },
            text: "The report"
        )
    }

    /// `page` drawn as Settings' window draws it.
    private func draws(_ page: SettingsPage, _ model: SettingsModel, height: CGFloat = 600) -> Bool {
        drawn(pageView(page, model), width: Self.pageWidth, height: height).height > 0
    }

    /// `page` as Settings' window shows it, beside its sidebar.
    private func pageView(_ page: SettingsPage, _ model: SettingsModel) -> some View {
        let navigation = SettingsNavigation()
        navigation.page = page
        return SettingsPageView(model: model, navigation: navigation).environment(SettingsKeys().page)
    }

    /// How wide Settings' pages are, as its window opens.
    private static let pageWidth = SettingsWindowController.initialSize.width - SettingsWindowController.sidebarWidth
}
