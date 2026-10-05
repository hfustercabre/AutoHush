import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerOption")
@MainActor
struct PlayerOptionTests {
    @Test("every player in the catalog is offered, in its order, with where it's installed")
    func list() {
        let catalog = MusicPlayerCatalog(players: [
            MockMusicPlayer(bundleID: "com.example.first", name: "First"),
            MockMusicPlayer(bundleID: "com.example.second", name: "Second"),
        ])
        let url = URL(fileURLWithPath: "/Applications/Second.app")
        let options = PlayerOption.list(catalog) { $0 == "com.example.second" ? url : nil }

        #expect(options == [
            PlayerOption(bundleID: "com.example.first", name: "First", appURL: nil),
            PlayerOption(bundleID: "com.example.second", name: "Second", appURL: url),
        ])
        #expect(options.map(\.isInstalled) == [false, true])
        #expect(!options.noneInstalled)
        #expect([options[0]].noneInstalled)
    }
}
