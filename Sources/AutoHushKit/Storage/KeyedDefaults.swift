import Foundation

/// A dictionary by bundle ID kept under one key of the preferences, and
/// changed from several queues: each change reads it whole and writes it
/// back, under one lock (S11, the full check, 2026-10-19: the added apps'
/// setups and the web apps' recipes kept a lock each).
package struct KeyedDefaults: Sendable {
    /// Held by every change to any of them, and by `Preferences` clearing
    /// out old recipes.
    static let lock = NSLock()

    let key: String
    /// The preferences' suite; `nil` for AutoHush's own.
    private let suiteName: String?
    /// Preferences given in place of a suite (tests keep theirs in memory):
    /// UserDefaults can be used from several threads at once (its
    /// documentation), though it isn't marked Sendable.
    nonisolated(unsafe) private let given: UserDefaults?

    package init(key: String, suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
        given = nil
    }

    /// Kept in `defaults` (B8, the full check, 2026-10-27: a suite named by
    /// a path, as tests used, can hand back an older value).
    package init(key: String, defaults: UserDefaults) {
        self.key = key
        suiteName = nil
        given = defaults
    }

    private var defaults: UserDefaults { given ?? suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// The values as stored, by bundle ID; empty when there are none.
    package func values() -> [String: Any] {
        defaults.dictionary(forKey: key) ?? [:]
    }

    /// Sets one value, or removes it (`nil`).
    package func set(_ value: Any?, for id: String) {
        change { stored in
            guard let value else { return stored.removeValue(forKey: id) != nil }
            stored[id] = value
            return true
        }
    }

    /// Reads the dictionary, changes it and writes it back, under the lock;
    /// nothing is written when `body` returns `false` (nothing changed).
    package func change(_ body: (inout [String: Any]) -> Bool) {
        let defaults = defaults
        Self.lock.withLock {
            var stored = defaults.dictionary(forKey: key) ?? [:]
            if body(&stored) { defaults.set(stored, forKey: key) }
        }
    }
}
