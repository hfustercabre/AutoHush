import os
import Testing
import AutoHushKit
import AutoHushTestSupport

@Suite("MusicPlayerCatalog")
struct MusicPlayerCatalogTests {
    @Test("players are found by bundle ID, in the order they're offered")
    func lookup() {
        let first = MockMusicPlayer(bundleID: "com.example.first", name: "First")
        let second = MockMusicPlayer(bundleID: "com.example.second", name: "Second")
        let catalog = MusicPlayerCatalog(players: [first, second], formerDefault: "com.example.first")

        #expect(catalog.players.map(\.name) == ["First", "Second"])
        #expect(catalog.player(bundleID: "com.example.second")?.name == "Second")
        #expect(catalog.player(bundleID: "com.example.unknown") == nil)
        #expect(catalog.player(bundleID: nil) == nil)
        #expect(catalog.formerDefault == "com.example.first")
    }

    @Test("players found on this Mac come after the built-in ones, looked up each time")
    func found() {
        let first = MockMusicPlayer(bundleID: "com.example.first", name: "First")
        let webApp = MockMusicPlayer(bundleID: "com.example.web", name: "Web")
        let catalog = MusicPlayerCatalog(players: [first], found: { [webApp] })
        #expect(catalog.players.map(\.name) == ["First"])
        #expect(catalog.all.map(\.name) == ["First", "Web"])
        #expect(catalog.player(bundleID: "com.example.web")?.name == "Web")
        #expect(first.kind == .app)
    }

    @Test("a player says nothing of where it's installed or of being untested, unless it knows")
    func defaults() {
        let player = MockMusicPlayer(bundleID: "com.example.first", name: "First")
        #expect(player.installedURL == nil)
        #expect(!player.isUntested)
    }

    @Test("suggested web apps are looked up each time, and aren't players")
    func suggestions() {
        let added = OSAllocatedUnfairLock(initialState: false)
        let catalog = MusicPlayerCatalog(players: [], suggested: {
            added.withLock { $0 } ? [] : [WebAppSuggestion(name: "Deezer", address: "deezer.com")]
        })
        #expect(catalog.webAppSuggestions == [WebAppSuggestion(name: "Deezer", address: "deezer.com")])
        #expect(catalog.all.isEmpty)
        added.withLock { $0 = true }
        #expect(catalog.webAppSuggestions.isEmpty)
        #expect(MusicPlayerCatalog(players: []).webAppSuggestions.isEmpty)
    }
}
