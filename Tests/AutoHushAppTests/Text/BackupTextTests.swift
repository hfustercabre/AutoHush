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
        (PlayerControls.choosing(), "AppleScript · backups on · panel while muted on"),
        (.choosing(switches: BackupSwitches(panelWhileMuted: false)), "AppleScript · backups on · panel while muted off"),
        // The panel's switch is dimmed while the backups are off: not listed.
        (.choosing(switches: BackupSwitches(usesBackups: false)), "AppleScript · backups off"),
        // The chosen main control by its name.
        (.choosing(.menu), "Its playback menu · backups on · panel while muted on"),
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

    @Test("the pop-up names the recommended control so; the row is named as a web app's")
    func names() {
        #expect(BackupText.recommended("AppleScript") == "AppleScript (Recommended)")
        #expect(BackupText.mainControlRow == "Main control")
        #expect(BackupText.controls == "Controls")
    }
}
