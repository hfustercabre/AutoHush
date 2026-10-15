import Foundation
import Testing
@testable import AutoHushApp
import CheckedPlayers

@Suite("KeptCheck")
struct KeptCheckTests {
    @Test("a finished check is kept a day at most, and forgotten")
    func keeping() {
        let store = KeptCheckStore(defaults: UserDefaults(suiteName: "KeptCheckTests-\(UUID().uuidString)")!)
        let app = CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), browserName: "Brave Browser")
        let kept = KeptCheck(app: app, result: CheckResult(ways: [], setup: nil), at: Date(timeIntervalSince1970: 1000))
        store.save(kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + 60)) == kept)
        #expect(store.load(now: Date(timeIntervalSince1970: 1000 + KeptCheck.maxAge)) == nil)
        store.forget()
        #expect(store.load(now: Date(timeIntervalSince1970: 1000)) == nil)
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
