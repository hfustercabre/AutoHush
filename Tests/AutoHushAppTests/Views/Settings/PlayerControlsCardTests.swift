import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// Settings → Fine-Tuning's player card: the Main control row's ← and →
/// (T-8, the full check, 2026-11-06); its chips while its controls can't be
/// used, and its note while backups stand in (D4, D5, 2026-11-07).
@Suite("PlayerControlsCard")
@MainActor
struct PlayerControlsCardTests {
    private let script = PlayerControls.Control(kind: .script, result: .init(kind: .script, mark: .works))
    private let menu = PlayerControls.Control(kind: .menu, result: .init(kind: .menu, mark: .works))
    private let panel = PlayerControls.Control(kind: .panel, result: .init(kind: .panel, mark: .works))

    @Test("← and → step through the main controls in the pop-up's order, the panel last, and stop at its ends")
    func stepping() {
        // The panel second among them, as they're pressed: last in the pop-up.
        let all = [script, panel, menu]
        let fromMenu = PlayerControls(all: all, chosen: .menu, choosable: { _, _ in true }, switches: BackupSwitches())
        #expect(PlayerControlsCard.steppedMainControl(fromMenu, by: 1) == .panel)
        #expect(PlayerControlsCard.steppedMainControl(fromMenu, by: -1) == .script)
        let fromPanel = PlayerControls(all: all, chosen: .panel, choosable: { _, _ in true }, switches: BackupSwitches())
        #expect(PlayerControlsCard.steppedMainControl(fromPanel, by: -1) == .menu)
        #expect(PlayerControlsCard.steppedMainControl(fromPanel, by: 1) == .panel) // the end
        let fromOwn = PlayerControls(all: all, chosen: nil, choosable: { _, _ in true }, switches: BackupSwitches())
        #expect(PlayerControlsCard.steppedMainControl(fromOwn, by: -1) == .script) // the start
    }

    @Test("a control not learned yet, dimmed in the pop-up, is stepped over")
    func notLearnedSkipped() {
        let page = PlayerControls.Control(kind: .page, result: nil)
        let controls = PlayerControls(all: [script, page, panel], chosen: nil,
                                      choosable: { control, index in index == 0 || control.kind == .panel },
                                      switches: BackupSwitches(), notYet: { control, _ in control.kind == .page })
        #expect(controls.listedChoices.map(\.kind) == [.script, .page, .panel])
        #expect(PlayerControlsCard.steppedMainControl(controls, by: 1) == .panel)
    }

    @Test("controls that can't be used yet offer their fix: Check Again… for an app added before backups were kept, Learn Controls… for a web app not learned (D4)")
    func unusableFixes() {
        let actions = FakeAppActions()
        #expect(PlayerControlsCard.Unusable(.choosing()) == nil)
        let checkAgain = PlayerControlsCard.Unusable(.choosing(needsCheckAgain: true))
        #expect(checkAgain == .needsCheckAgain && checkAgain?.button == ControlErrorFix.checkAgain.title)
        let notLearned = PlayerControlsCard.Unusable(.choosing(notLearned: true))
        #expect(notLearned == .notLearned && notLearned?.button == LearnText.learnButton)
        #expect(notLearned?.note("Jukebox") == AppStatus.controlsNotLearnedLine)
        checkAgain?.fix(actions)
        notLearned?.fix(actions)
        #expect(actions.log.calls == ["checkPlayerAgain", "learnAgain"])
    }

    @Test("while backups stand in for the player's own permission, the card says so under Use backup controls (D5)")
    func standInNote() async {
        let actions = FakeAppActions()
        let height = { (model: SettingsModel) in drawn(PlayerControlsCard(model: model), width: 520, height: 900).height }
        let standingIn = await SettingsModel.withAutomation(OSStatus(errAEEventNotPermitted), actions: actions)
        let allowed = await SettingsModel.withAutomation(noErr, actions: actions)
        #expect(standingIn.backupsStandIn != nil && allowed.backupsStandIn == nil)
        #expect(height(standingIn) > height(allowed))
    }
}
