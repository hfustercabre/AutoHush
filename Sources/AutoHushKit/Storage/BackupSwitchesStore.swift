import Foundation

/// A built-in player's backup switches (the user, 2026-11-04): whether its
/// backups are pressed when its own way fails, and whether the Now Playing
/// panel is among them while it's muted in place of a pause. Both on until
/// the user turns one off. An app added with Add an App keeps its own in
/// its setup (`PlayerSetup`).
package struct BackupSwitches: Equatable, Sendable {
    package var usesBackups: Bool
    package var panelWhileMuted: Bool
    /// The control the user chose as its main one in Settings (a
    /// `WayOrder.Kind`'s raw value: "script", "menu", "page", "panel");
    /// `nil` for the one its check recommended or chose at Use (the user,
    /// 2026-11-05: F4).
    package var mainControl: String?

    package init(usesBackups: Bool = true, panelWhileMuted: Bool = true, mainControl: String? = nil) {
        self.usesBackups = usesBackups
        self.panelWhileMuted = panelWhileMuted
        self.mainControl = mainControl
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

    /// The player's switches; both on, and its own main control, when none were set.
    package func switches(for bundleID: String) -> BackupSwitches {
        let values = stored.values()[bundleID] as? [String: Any] ?? [:]
        return BackupSwitches(usesBackups: values["usesBackups"] as? Bool ?? true,
                              panelWhileMuted: values["panelWhileMuted"] as? Bool ?? true,
                              mainControl: values["mainControl"] as? String)
    }

    package func set(_ switches: BackupSwitches, for bundleID: String) {
        var values: [String: Any] = ["usesBackups": switches.usesBackups, "panelWhileMuted": switches.panelWhileMuted]
        if let main = switches.mainControl { values["mainControl"] = main }
        stored.set(values, for: bundleID)
    }
}
