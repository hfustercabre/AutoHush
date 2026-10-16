import Foundation
import Testing
@testable import AutoHushApp
import CheckedPlayers

@Suite("KeptCheck")
struct KeptCheckTests {
    @Test("a finished check is kept a day at most (then forgotten once found), with how its Reopen step went, and forgotten; one an earlier build kept still opens")
    func keeping() throws {
        let store = KeptCheckStore(defaults: UserDefaults(suiteName: "KeptCheckTests-\(UUID().uuidString)")!)
        let app = CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), browserName: "Brave Browser")
        let kept = KeptCheck(app: app, result: CheckResult(ways: [], setup: nil), at: Date(timeIntervalSince1970: 1000),
                             needsReopen: true, reopenOutcome: .skipped)
        store.save(kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + 60)) == kept)
        store.forget()
        #expect(store.load(now: Date(timeIntervalSince1970: 1000)) == nil)
        store.save(kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + KeptCheck.maxAge)) == nil)
        #expect(store.defaults.data(forKey: KeptCheckStore.key) == nil)

        // Kept before the Reopen step's fields were: none of them.
        var old = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any])
        old["needsReopen"] = nil
        old["reopenOutcome"] = nil
        store.defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: KeptCheckStore.key)
        let reopened = KeptCheck(app: app, result: kept.result, at: kept.at)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + 60)) == reopened)
    }

    @Test("the players reopened always, by bundle ID")
    func reopenChoices() {
        let defaults = UserDefaults(suiteName: "KeptCheckTests-\(UUID().uuidString)")!
        #expect(!ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
        ReopenChoices.setReopensAlways("com.deezer.deezer-desktop", defaults: defaults)
        #expect(ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
        ReopenChoices.setReopensAlways("com.deezer.deezer-desktop", false, defaults: defaults)
        #expect(!ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
    }
}
