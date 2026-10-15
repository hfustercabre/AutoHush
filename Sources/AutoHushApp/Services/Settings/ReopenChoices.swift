import Foundation

/// The players the user chose to reopen with the option they need whenever
/// they're found opened without it (the reopen alert's checkbox), by bundle
/// ID, so AutoHush no longer asks.
enum ReopenChoices {
    static let key = "reopensPlayersAlways"

    static func reopensAlways(_ bundleID: String, defaults: UserDefaults = .standard) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(bundleID)
    }

    static func setReopensAlways(_ bundleID: String, _ always: Bool = true, defaults: UserDefaults = .standard) {
        var ids = Set(defaults.stringArray(forKey: key) ?? [])
        if always { ids.insert(bundleID) } else { ids.remove(bundleID) }
        defaults.set(ids.sorted(), forKey: key)
    }
}
