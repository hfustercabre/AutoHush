/// A built-in player's backup switches (the user, 2026-11-04): whether its
/// backups are pressed when its own way fails (on until the user turns it
/// off), and whether the Now Playing panel is among them while it's muted in
/// place of a pause (off until the user turns it on). An app added with Add
/// an App keeps its own in its setup (`PlayerSetup`).
///
/// `BackupSwitches()` holds the defaults: everything that starts a player's
/// switches, or puts them back, takes them from it.
package struct BackupSwitches: Equatable, Sendable {
    package var usesBackups: Bool
    package var panelWhileMuted: Bool
    /// The control the user chose as its main one in Settings; `nil` for
    /// the one its check recommended or chose at Use (the user,
    /// 2026-11-05: F4).
    package var mainControl: MainControl?

    /// The panel while muted is off by default (the user, 2026-11-06: it
    /// shows on screen for a moment each time it's pressed).
    package init(usesBackups: Bool = true, panelWhileMuted: Bool = false, mainControl: MainControl? = nil) {
        self.usesBackups = usesBackups
        self.panelWhileMuted = panelWhileMuted
        self.mainControl = mainControl
    }
}
