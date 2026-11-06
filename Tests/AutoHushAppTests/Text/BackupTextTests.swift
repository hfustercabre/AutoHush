import Testing
@testable import AutoHushApp
import AutoHushKit
import CheckedPlayers

/// The player's controls in words (F4 + F5, the user's pick, 2026-11-05):
/// Fine-Tuning's pop-up items, and Media Player's Controls row's value,
/// what the card shows.
@Suite("The player's controls' texts")
struct BackupTextTests {
    @Test("Media Player's row lists the main control, the backups' switch, and the panel's while it's a backup and counts", arguments: [
        (PlayerControls.choosing(), "AppleScript · backups on · panel while muted off"), // the defaults
        (.choosing(switches: BackupSwitches(panelWhileMuted: true)), "AppleScript · backups on · panel while muted on"),
        // The panel's switch is dimmed while the backups are off: not listed.
        (.choosing(switches: BackupSwitches(usesBackups: false)), "AppleScript · backups off"),
        // The chosen main control by its name.
        (.choosing(.menu), "Its playback menu · backups on · panel while muted off"),
        // The panel as the main control has no switch: not listed.
        (.choosing(.panel, switches: BackupSwitches(mainControl: "panel")),
         "The menu bar’s Now Playing panel · backups on"),
    ])
    func summary(_ controls: PlayerControls, _ expected: String) {
        #expect(BackupText.summary(controls) == expected)
    }

    @Test("without the panel among its controls, no panel switch is listed")
    func summaryWithoutPanel() {
        let controls = PlayerControls(main: .init(kind: .menu, result: .init(kind: .menu, mark: .works)),
                                      backups: [.init(kind: .mediaKey, result: nil)], switches: BackupSwitches())
        #expect(!controls.hasPanel && !controls.hasPanelBackup)
        #expect(BackupText.summary(controls) == "Its playback menu · backups on")
    }

    @Test("an app to check again, or a web app not learned yet, says its backups are off, as its dimmed switch shows")
    func summaryUnavailable() {
        #expect(BackupText.summary(.choosing(needsCheckAgain: true)) == "AppleScript · backups off")
        let page = PlayerControls(main: .init(kind: .page, result: nil), backups: [.init(kind: .panel, result: nil)],
                                  switches: BackupSwitches(), notLearned: true)
        #expect(BackupText.summary(page) == "Its page’s Play/Pause · backups off")
    }

    @Test("the row is named as a web app's")
    func names() {
        #expect(BackupText.mainControlRow == "Main control")
        #expect(BackupText.controls == "Controls")
    }

    @Test("each pop-up item says how its check found it in words, the recommended one so named (VO7b)", arguments: [
        (WayOrder.Kind.script, "AppleScript (Recommended, works)"),
        (.menu, "Its playback menu (works)"),
        (.page, "Its page’s Play/Pause (works in some states)"),
        (.panel, "The menu bar’s Now Playing panel (works)"),
    ])
    func itemTitles(_ kind: WayOrder.Kind, _ expected: String) throws {
        let controls = PlayerControls.choosing()
        let control = try #require(controls.listedChoices.first { $0.kind == kind })
        #expect(PlayerControlsCard.itemTitle(control, recommended: kind == controls.recommended, notYet: false) == expected)
    }

    @Test("a control that didn't work, or that no check tried, says so; one not learned yet, only that (VO7b)")
    func itemTitlesOtherResults() {
        let failed = PlayerControls.Control(kind: .menu, result: .init(kind: .menu, mark: .none))
        #expect(PlayerControlsCard.itemTitle(failed, recommended: false, notYet: false) == "Its playback menu (didn’t work)")
        let untried = PlayerControls.Control(kind: .script, result: nil)
        #expect(PlayerControlsCard.itemTitle(untried, recommended: true, notYet: false) == "AppleScript (Recommended, not tried)")
        let page = PlayerControls.Control(kind: .page, result: .init(kind: .page, mark: .works))
        #expect(PlayerControlsCard.itemTitle(page, recommended: false, notYet: true) == "Its page’s Play/Pause (not learned yet)")
    }
}
