import Foundation
import CheckedPlayers

/// A check that finished, kept until its result is used, the app is changed
/// or another check replaces it, and at most `maxAge`: reopening AutoHush
/// (to apply Audio Recording) or closing the window doesn't cost another
/// three minutes.
struct KeptCheck: Codable, Equatable {
    static let maxAge: TimeInterval = 24 * 60 * 60

    let app: CheckableApp
    let result: CheckResult
    let at: Date
}

/// Where the last finished check is kept: AutoHush's preferences.
struct KeptCheckStore {
    static let key = "lastFinishedCheck"
    var defaults: UserDefaults = .standard

    func load(now: Date = Date()) -> KeptCheck? {
        guard let data = defaults.data(forKey: Self.key),
              let kept = try? JSONDecoder().decode(KeptCheck.self, from: data),
              now.timeIntervalSince(kept.at) < KeptCheck.maxAge else { return nil }
        return kept
    }

    func save(_ kept: KeptCheck) {
        guard let data = try? JSONEncoder().encode(kept) else { return }
        defaults.set(data, forKey: Self.key)
    }

    func forget() {
        defaults.removeObject(forKey: Self.key)
    }
}
