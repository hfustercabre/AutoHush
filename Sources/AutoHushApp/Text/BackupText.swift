import Foundation
import AutoHushKit
import CheckedPlayers

/// A player's controls (the user, 2026-11-05: B1, "Backup controls",
/// Details… in Settings; F4 + F5, its main control chosen in Fine-Tuning):
/// Settings → Fine-Tuning's card and Media Player's row to it, Add an App's
/// last step, the Details sheet and Diagnostics.
enum BackupText {
    static let uses = String(localized: "Use backup controls",
                             comment: "Switch in Settings → Fine-Tuning (the player's card) and Add an App's last step, and a row in Settings → Diagnostics: when the player's main control fails, AutoHush tries its other ways to pause and play it (its menu, its page, the keyboard's Play/Pause key, the menu bar's Now Playing panel)")
    static let usesSubtitle = String(localized: "Tries another one when one fails",
                                     comment: "Under the switch “Use backup controls”: AutoHush tries another of the player's controls when one fails to pause or play it")
    static let panelWhileMuted = String(localized: "Use the Now Playing panel while muted",
                                        comment: "Switch under “Use backup controls”, and a row in Settings → Diagnostics: while AutoHush mutes the player because it didn't pause, it may also press its row in the menu bar's Now Playing panel, once")
    static let panelSubtitle = String(localized: "Opens on screen for a moment",
                                      comment: "Under the switch “Use the Now Playing panel while muted”: the Now Playing panel shows on screen briefly when it's pressed")
    static let off = String(localized: "Use backup controls is off",
                            comment: "Settings → Fine-Tuning, the player's card: note under the dimmed “Use the Now Playing panel while muted” while the switch above it is off")
    static func checkAgain(_ app: String) -> String {
        String(localized: "Check \(app) again to use backup controls.",
               comment: "Settings → Fine-Tuning, the player's card: note for an app added with Add an App before backup controls were kept; a check gives it some. %@ is the app's name")
    }
    static let details = String(localized: "Details…",
                                comment: "Button in Settings → Fine-Tuning, the player's card: opens the list of the player's main control and backup controls, and how each works")
    static let mainControl = String(localized: "Main Control",
                                    comment: "Heading in the controls' Details sheet: the way AutoHush pauses and plays the player first")
    static let backupControls = String(localized: "Backup Controls",
                                       comment: "Heading in the controls' Details sheet: the player's other ways to pause and play it, tried when the main one fails")
    static let key = String(localized: "The Play/Pause key",
                            comment: "A backup control: the keyboard's Play/Pause key (the controls' Details sheet, Settings → Diagnostics under “Controlled by”)")
    static func keyNote(_ app: String) -> String {
        String(localized: "Only while \(app) is Now Playing",
               comment: "The controls' Details sheet, under “The Play/Pause key”: AutoHush presses it only while macOS counts the player as Now Playing. %@ is the player's name")
    }

    // MARK: - Settings → Fine-Tuning's card, and Media Player's row to it

    /// The card's first row: a pop-up of the controls that can be its main
    /// one, or its one control, read only.
    static let mainControlRow = String(localized: "Main control",
                                       comment: "Settings → Fine-Tuning, the player's card: title of its first row, beside a pop-up of the controls AutoHush can pause and play the player by first (or beside its only one)")
    /// An item of the pop-up: the control AutoHush recommends.
    static func recommended(_ control: String) -> String {
        String(localized: "\(control) (Recommended)",
               comment: "Settings → Fine-Tuning, the player's card: an item of the “Main control” pop-up, the control AutoHush recommends (the player's own, or the one chosen in Add an App). %@ is the control (AppleScript, Its playback menu…)")
    }
    /// An item of the pop-up, dimmed: a control that can be the main one
    /// once AutoHush has learned it (a built-in player's page, 2026-11-05).
    static func notLearnedYet(_ control: String) -> String {
        String(localized: "\(control) (not learned yet)",
               comment: "Settings → Fine-Tuning, the player's card: a dimmed item of the “Main control” pop-up, a control that can't be chosen until AutoHush has learned its Play/Pause button (it learns it the first time it pauses the player another way). %@ is the control (Its page’s Play/Pause)")
    }
    /// Media Player's row to the card: the word of a web app's Controls row.
    static var controls: String { LearnText.controlsTitle }
    static let backupsOn = String(localized: "backups on",
                                  comment: "Settings → Media Player, the “Controls” row's value after the main control's name (“AppleScript · backups on”): the switch “Use backup controls” is on. Lowercase, as a part of a list")
    static let backupsOff = String(localized: "backups off",
                                   comment: "Settings → Media Player, the “Controls” row's value after the main control's name (“AppleScript · backups off”): the switch “Use backup controls” is off. Lowercase, as a part of a list")
    static let panelOn = String(localized: "panel while muted on",
                                comment: "Settings → Media Player, the “Controls” row's value, last (“AppleScript · backups on · panel while muted on”): the switch “Use the Now Playing panel while muted” is on. Lowercase, as a part of a list")
    static let panelOff = String(localized: "panel while muted off",
                                 comment: "Settings → Media Player, the “Controls” row's value, last (“AppleScript · backups on · panel while muted off”): the switch “Use the Now Playing panel while muted” is off. Lowercase, as a part of a list")

    /// Media Player's Controls row's value (F5, the user's pick,
    /// 2026-11-05): the main control's name, whether the backups are used,
    /// and the panel's switch while it shows and counts, as the card shows
    /// them ("AppleScript · backups on · panel while muted on"): an app to
    /// check again, or a web app not learned yet, with its switch off.
    static func summary(_ controls: PlayerControls) -> String {
        let shown = !controls.needsCheckAgain && !controls.notLearned
        let usesBackups = shown && controls.switches.usesBackups
        var parts = [WayText.control(controls.main.kind), usesBackups ? backupsOn : backupsOff]
        if usesBackups, controls.hasPanel { parts.append(controls.switches.panelWhileMuted ? panelOn : panelOff) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Diagnostics, under “Controlled by”

    static func backup(_ control: String) -> String {
        String(localized: "\(control) (backup)",
               comment: "Settings → Diagnostics, under “Controlled by”: one of the player's backup controls. %@ is the control (Its playback menu…)")
    }
    static func marked(_ control: String, _ mark: String) -> String {
        String(localized: "\(control) (\(mark))",
               comment: "Settings → Diagnostics, under “Controlled by”: the player's main control, and when it was last used. %1$@ is the control (AppleScript…), %2$@ is “paused last”, “played last” or “paused and played last”")
    }
    static func backupMarked(_ control: String, _ mark: String) -> String {
        String(localized: "\(control) (backup, \(mark))",
               comment: "Settings → Diagnostics, under “Controlled by”: a backup control, and when it was last used. %1$@ is the control (Its playback menu…), %2$@ is “paused last”, “played last” or “paused and played last”")
    }
    static let pausedLast = String(localized: "paused last",
                                   comment: "Settings → Diagnostics, under “Controlled by”, in brackets after a control: it paused the player last")
    static let playedLast = String(localized: "played last",
                                   comment: "Settings → Diagnostics, under “Controlled by”, in brackets after a control: it played the player last")
    static let pausedAndPlayedLast = String(localized: "paused and played last",
                                            comment: "Settings → Diagnostics, under “Controlled by”, in brackets after a control: it paused and played the player last")
}
