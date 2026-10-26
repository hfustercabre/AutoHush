import Foundation
import Testing
@testable import PlayerCheckKit
import WebAppPlayers
import AutoHushTestSupport

@Suite("SavedButtonStore")
struct SavedButtonStoreTests {
    /// The store's folder, a test's own, removed after it.
    private let folder = TemporaryFolder("SavedButtonStoreTests", create: false)
    private var file: URL { folder.appending(path: "button-places.json") }

    @Test("each app's button is kept whole, its recipe and its row too")
    func keeps() throws {
        let store = SavedButtonStore(file: file)
        #expect(store.all().isEmpty)
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [ButtonPlace(path: ["AXGroup"], distanceFromBottom: 40)])
        store.change("com.example.a") { $0.path = ButtonPath(root: .page, path: [0, 2, 1]) }
        store.change("com.example.a") { $0.recipe = SavedRecipe(recipe) }
        store.change("com.example.b") { $0.panelRow = "Song, Artist – Album" }
        let all = store.all()
        #expect(all["com.example.a"]?.path == ButtonPath(root: .page, path: [0, 2, 1]))
        #expect(all["com.example.a"]?.recipe?.recipe == recipe)
        #expect(all["com.example.b"]?.panelRow == "Song, Artist – Album")
    }

    @Test("a file from before recipes keeps its paths")
    func paths() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(["com.example.a": ButtonPath(root: .window, path: [3])]).write(to: file)
        #expect(SavedButtonStore(file: file).all()["com.example.a"]?.path == ButtonPath(root: .window, path: [3]))
    }
}
