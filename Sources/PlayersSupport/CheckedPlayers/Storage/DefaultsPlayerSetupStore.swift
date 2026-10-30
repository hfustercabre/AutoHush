import Foundation
import AutoHushKit

/// The setups in AutoHush's preferences, each as JSON by bundle ID.
struct DefaultsPlayerSetupStore: PlayerSetupStore {
    static let key = "checkedPlayerSetups"
    private let stored: KeyedDefaults

    /// `suiteName`: the preferences' suite; `nil` for AutoHush's own.
    init(suiteName: String? = nil) {
        stored = KeyedDefaults(key: Self.key, suiteName: suiteName)
    }

    /// Kept in `defaults` (tests keep theirs in memory).
    init(defaults: UserDefaults) {
        stored = KeyedDefaults(key: Self.key, defaults: defaults)
    }

    /// The setups that can be read, by name; one that can't is left out.
    func setups() -> [PlayerSetup] {
        stored.values().values.compactMap { ($0 as? Data).flatMap { try? JSONDecoder().decode(PlayerSetup.self, from: $0) } }
            .sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    func save(_ setup: PlayerSetup) {
        guard let data = try? JSONEncoder().encode(setup) else { return }
        stored.set(data, for: setup.bundleID)
    }

    func forget(_ bundleID: String) {
        stored.set(nil, for: bundleID)
    }

    /// Read, changed and saved under the lock: a change (a panel row kept,
    /// a moved app's place) can't bring back a setup the user removed
    /// meanwhile, nor put its old ways over a new check's.
    func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {
        stored.change { setups in
            guard let data = setups[bundleID] as? Data, var setup = try? JSONDecoder().decode(PlayerSetup.self, from: data) else { return false }
            change(&setup)
            guard let changed = try? JSONEncoder().encode(setup) else { return false }
            setups[bundleID] = changed
            return true
        }
    }
}
