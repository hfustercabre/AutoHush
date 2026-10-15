import Foundation
import Testing
@testable import CheckedPlayers
import AutoHushKit

/// The panel in memory: its rows, the one pressed.
private final class FakePanel: NowPlayingPanel, @unchecked Sendable {
    private let lock = NSLock()
    private var shown: [PanelRow]
    private var pressedRows: [String] = []
    var opens = true
    var inMenuBar = true

    init(_ rows: [PanelRow]) { shown = rows }

    var pressed: [String] { lock.withLock { pressedRows } }

    func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        guard opens else { return nil }
        let rows = lock.withLock { shown }
        guard let row = pick(rows) else { return false }
        lock.withLock { pressedRows.append(row.text) }
        return true
    }

    func isInMenuBar() -> Bool { inMenuBar }
}

@Suite("PanelWay")
struct PanelWayTests {
    private let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"),
                                    ways: [.menu(menuName: "Play"), .panel(rememberedRow: nil)])
    private let rows = [PanelRow(text: "Song, Artist – Album", playing: true), PanelRow(text: "Other Song, Someone – Else", playing: true)]

    private func way(_ panel: FakePanel, store: MemoryStore, running: Bool = true, titles: [String] = ["Song – Artist"],
                     remembered: String? = nil) -> PanelWay {
        PanelWay(setup: setup, remembered: remembered, store: store, panel: panel, processIdentifier: { running ? 4242 : nil },
                 shown: { _ in PanelWay.Shown(titles: titles, otherApps: ["Finder"], holdsNowPlaying: false) })
    }

    @Test("it presses the row showing what the app plays, and keeps that row in the setup kept now")
    func pressesItsRow() async throws {
        let store = MemoryStore()
        var kept = setup
        kept.stateNotification = "checked again since"
        store.save(kept)
        let panel = FakePanel(rows)
        try await way(panel, store: store).pause()
        #expect(panel.pressed == ["Song, Artist – Album"])
        let saved = try #require(store.setups().first)
        #expect(saved.ways == [.menu(menuName: "Play"), .panel(rememberedRow: "Song, Artist – Album")])
        #expect(saved.stateNotification == "checked again since") // only its row changed
        #expect(await way(panel, store: store).playerState() == .unknown) // its state is its other signs'
    }

    @Test("a setup no longer kept isn't added back, nor one without the panel any more")
    func notAddedBack() async throws {
        let store = MemoryStore()
        try await way(FakePanel(rows), store: store).pause()
        #expect(store.setups().isEmpty)
        store.save(PlayerSetup(bundleID: setup.bundleID, name: "Jukebox", appURL: setup.appURL, ways: [.menu(menuName: "Play")]))
        try await way(FakePanel(rows), store: store).pause()
        #expect(store.setups().first?.ways == [.menu(menuName: "Play")])
    }

    @Test("with no row of its own, nothing is pressed; not running, nothing is asked; Now Playing hidden in the menu bar says so")
    func noRow() async {
        let store = MemoryStore()
        let panel = FakePanel(rows)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) {
            try await way(panel, store: store, titles: ["Nothing like it"]).pause()
        }
        #expect(panel.pressed.isEmpty)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await way(panel, store: store, running: false).play() }
        let closed = FakePanel(rows)
        closed.opens = false
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) { try await way(closed, store: store).pause() }
        // Hidden in the menu bar (System Settings): says so, for the user to show it.
        let hidden = FakePanel(rows)
        hidden.opens = false
        hidden.inMenuBar = false
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nowPlayingHidden)) { try await way(hidden, store: store).pause() }
    }

    @Test("else the row it changed with before")
    func remembered() async throws {
        let panel = FakePanel([PanelRow(text: "Other Song, Someone – Else", playing: false)])
        try await way(panel, store: MemoryStore(), titles: [], remembered: "Other Song, Someone – Else").play()
        #expect(panel.pressed == ["Other Song, Someone – Else"])
    }
}
