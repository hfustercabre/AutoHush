import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers

@Suite("KeptCheck")
struct KeptCheckTests {
    private let app = CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), browserName: "Brave Browser")

    /// A check finished at 1000 s, whose Reopen step was skipped.
    private var kept: KeptCheck {
        KeptCheck(app: app, result: CheckResult(ways: [], setup: nil), at: Date(timeIntervalSince1970: 1000),
                  needsReopen: true, reopenOutcome: .skipped)
    }

    @Test("a finished check is kept, with how its Reopen step went")
    func keeping() {
        let store = KeptCheckStore(defaults: MemoryDefaults())
        store.save(kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + 60)) == kept)
    }

    @Test("a kept check can be forgotten")
    func forgetting() {
        let store = KeptCheckStore(defaults: MemoryDefaults())
        store.save(kept)
        store.forget()
        #expect(store.load(now: Date(timeIntervalSince1970: 1000)) == nil)
    }

    @Test("a check is kept a day at most, then forgotten once found")
    func keptADayAtMost() {
        let store = KeptCheckStore(defaults: MemoryDefaults())
        store.save(kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + KeptCheck.maxAge)) == nil)
        #expect(store.defaults.data(forKey: KeptCheckStore.key) == nil)
    }

    @Test("a check an earlier build kept, before the Reopen step's fields were, still opens")
    func keptByAnEarlierBuild() throws {
        let store = KeptCheckStore(defaults: MemoryDefaults())
        var old = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any])
        old["needsReopen"] = nil
        old["reopenOutcome"] = nil
        store.defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: KeptCheckStore.key)
        let reopened = KeptCheck(app: app, result: kept.result, at: kept.at)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + 60)) == reopened)
    }

    @Test("the players reopened always, by bundle ID")
    func reopenChoices() {
        let defaults = MemoryDefaults()
        #expect(!ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
        ReopenChoices.setReopensAlways("com.deezer.deezer-desktop", defaults: defaults)
        #expect(ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
        ReopenChoices.setReopensAlways("com.deezer.deezer-desktop", false, defaults: defaults)
        #expect(!ReopenChoices.reopensAlways("com.deezer.deezer-desktop", defaults: defaults))
    }
}
