import Foundation

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

    /// The player's switches; the defaults (`BackupSwitches()`), and its own
    /// main control, when none were set.
    package func switches(for bundleID: String) -> BackupSwitches {
        let values = stored.values()[bundleID] as? [String: Any] ?? [:]
        let defaults = BackupSwitches()
        return BackupSwitches(usesBackups: values["usesBackups"] as? Bool ?? defaults.usesBackups,
                              panelWhileMuted: values["panelWhileMuted"] as? Bool ?? defaults.panelWhileMuted,
                              mainControl: (values["mainControl"] as? String).map(MainControl.init(rawValue:)))
    }

    package func set(_ switches: BackupSwitches, for bundleID: String) {
        var values: [String: Any] = ["usesBackups": switches.usesBackups, "panelWhileMuted": switches.panelWhileMuted]
        if let main = switches.mainControl { values["mainControl"] = main.rawValue }
        stored.set(values, for: bundleID)
    }
}
