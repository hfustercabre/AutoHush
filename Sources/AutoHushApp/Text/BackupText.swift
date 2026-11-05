import Foundation

/// A player's backup controls (the user, 2026-11-05: B1, "Backup controls",
/// Details… in Settings): Settings → Media Player, Add an App's last step,
/// the Details sheet and Diagnostics.
enum BackupText {
    static let uses = String(localized: "Use backup controls",
                             comment: "Switch in Settings → Media Player and Add an App's last step, and a row in Settings → Diagnostics: when the player's main control fails, AutoHush tries its other ways to pause and play it (its menu, its page, the keyboard's Play/Pause key, the menu bar's Now Playing panel)")
    static let usesSubtitle = String(localized: "Tries another one when one fails",
                                     comment: "Under the switch “Use backup controls”: AutoHush tries another of the player's controls when one fails to pause or play it")
    static let panelWhileMuted = String(localized: "Use the Now Playing panel while muted",
                                        comment: "Switch under “Use backup controls”, and a row in Settings → Diagnostics: while AutoHush mutes the player because it didn't pause, it may also press its row in the menu bar's Now Playing panel, once")
    static let panelSubtitle = String(localized: "Opens on screen for a moment",
                                      comment: "Under the switch “Use the Now Playing panel while muted”: the Now Playing panel shows on screen briefly when it's pressed")
    static let off = String(localized: "Use backup controls is off",
                            comment: "Settings → Media Player: note under the dimmed “Use the Now Playing panel while muted” while the switch above it is off")
    static func checkAgain(_ app: String) -> String {
        String(localized: "Check \(app) again to use backup controls.",
               comment: "Settings → Media Player: note for an app added with Add an App before backup controls were kept; a check gives it some. %@ is the app's name")
    }
    static let details = String(localized: "Details…",
                                comment: "Button in Settings → Media Player: opens the list of the player's main control and backup controls, and how each works")
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
