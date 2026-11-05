import Foundation

/// A built-in player's backup switches (the user, 2026-11-04): whether its
/// backups are pressed when its own way fails, and whether the Now Playing
/// panel is among them while it's muted in place of a pause. Both on until
/// the user turns one off. An app added with Add an App keeps its own in
/// its setup (`PlayerSetup`).
package struct BackupSwitches: Equatable, Sendable {
    package var usesBackups: Bool
    package var panelWhileMuted: Bool

    package init(usesBackups: Bool = true, panelWhileMuted: Bool = true) {
        self.usesBackups = usesBackups
        self.panelWhileMuted = panelWhileMuted
    }
}

/// The built-in players' backup switches, by bundle ID, in the preferences
/// (`KeyedDefaults`): read at each press, from the players' own queues.
package struct BackupSwitchesStore: Sendable {
    static let key = "playerBackupSwitches"
    private let stored: KeyedDefaults

    package init(suiteName: String? = nil) {
        stored = KeyedDefaults(key: Self.key, suiteName: suiteName)
    }

    package init(defaults: UserDefaults) {
        stored = KeyedDefaults(key: Self.key, defaults: defaults)
    }

    /// The player's switches; both on when none were set.
    package func switches(for bundleID: String) -> BackupSwitches {
        let values = stored.values()[bundleID] as? [String: Bool] ?? [:]
        return BackupSwitches(usesBackups: values["usesBackups"] ?? true, panelWhileMuted: values["panelWhileMuted"] ?? true)
    }

    package func set(_ switches: BackupSwitches, for bundleID: String) {
        stored.set(["usesBackups": switches.usesBackups, "panelWhileMuted": switches.panelWhileMuted], for: bundleID)
    }
}
