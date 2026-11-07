import Testing
@testable import AutoHushApp
import AutoHushKit
import CheckedPlayers

/// Settings → Fine-Tuning's player card: the Main control row's ← and →
/// (T-8, the full check, 2026-11-06).
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
}
