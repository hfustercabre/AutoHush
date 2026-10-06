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
}
