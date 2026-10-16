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
    /// The app ran without its launch option: the Reopen step shows.
    var needsReopen = false
    /// How the Reopen step went (a Skip keeps Use from asking again).
    var reopenOutcome: AddAppModel.ReopenOutcome?
}

extension KeptCheck {
    /// A check kept by an earlier build has no Reopen step's fields: it's
    /// read as one whose app didn't need reopening.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        app = try values.decode(CheckableApp.self, forKey: .app)
        result = try values.decode(CheckResult.self, forKey: .result)
        at = try values.decode(Date.self, forKey: .at)
        needsReopen = try values.decodeIfPresent(Bool.self, forKey: .needsReopen) ?? false
        reopenOutcome = try values.decodeIfPresent(AddAppModel.ReopenOutcome.self, forKey: .reopenOutcome)
    }
}

/// Where the last finished check is kept: AutoHush's preferences.
struct KeptCheckStore {
    static let key = "lastFinishedCheck"
    var defaults: UserDefaults = .standard

    /// The kept check, unless it's older than `maxAge`: then it's forgotten.
    func load(now: Date = Date()) -> KeptCheck? {
        guard let data = defaults.data(forKey: Self.key),
              let kept = try? JSONDecoder().decode(KeptCheck.self, from: data) else { return nil }
        guard now.timeIntervalSince(kept.at) < KeptCheck.maxAge else {
            forget()
            return nil
        }
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
