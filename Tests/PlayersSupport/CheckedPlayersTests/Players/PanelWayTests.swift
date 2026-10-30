import Foundation
import Testing
@testable import CheckedPlayers
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

@Suite("PanelWay", .waitsTimeLimit)
struct PanelWayTests {
    private let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"),
                                    ways: [.menu(menuName: "Play"), .panel(rememberedRow: nil)])
    private let rows = [PanelRow(text: "Song, Artist – Album", playing: true), PanelRow(text: "Other Song, Someone – Else", playing: true)]

    private func way(_ panel: FakePanel, store: MemorySetupStore, running: Bool = true, titles: [String] = ["Song – Artist"],
                     remembered: String? = nil) -> PanelWay {
        PanelWay(setup: setup, remembered: remembered, store: store, panel: panel, processIdentifier: { running ? 4242 : nil },
                 shown: { _ in PanelWay.Shown(titles: titles, otherApps: ["Finder"], holdsNowPlaying: false) })
    }

    @Test("it presses the row showing what the app plays, and keeps that row in the setup kept now")
    func pressesItsRow() async throws {
        let store = MemorySetupStore()
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
        #expect(!way(panel, store: store).checksItsPresses) // and so are its presses' checks
        // Pressed through Accessibility, with no volume: no fades.
        #expect(way(panel, store: store).controlPermission == .accessibility(player: "Jukebox"))
        #expect(!way(panel, store: store).canFade)
        #expect(await way(panel, store: store).volume() == nil)
    }

    @Test("a setup no longer kept isn't added back, nor one without the panel any more")
    func notAddedBack() async throws {
        let store = MemorySetupStore()
        try await way(FakePanel(rows), store: store).pause()
        #expect(store.setups().isEmpty)
        store.save(PlayerSetup(bundleID: setup.bundleID, name: "Jukebox", appURL: setup.appURL, ways: [.menu(menuName: "Play")]))
        try await way(FakePanel(rows), store: store).pause()
        #expect(store.setups().first?.ways == [.menu(menuName: "Play")])
    }

    @Test("with no row of its own, nothing is pressed; not running, nothing is asked; Now Playing hidden in the menu bar says so")
    func noRow() async {
        let store = MemorySetupStore()
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

    @Test("a press the panel refuses fails, and its row isn't kept")
    func pressRefused() async {
        let store = MemorySetupStore()
        store.save(setup)
        let panel = FakePanel(rows)
        panel.pressFails = true
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) { try await way(panel, store: store).pause() }
        #expect(store.setups().first?.ways == setup.ways)
    }

    /// Its row always shows paused, as Qobuz's does.
    private let shownPaused = [PanelRow(text: "Jukebox,  – ", playing: false), PanelRow(text: "Other Song, Someone – Else", playing: true)]

    /// The way of a setup whose row doesn't follow the app: heard as
    /// `heard`, until a press toggles it (unless it ignores presses).
    private func staleWay(_ panel: FakePanel, heard: Bool?, ignores: Bool = false) -> PanelWay {
        var stale = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"),
                                ways: [.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        let hearing = LateHearing()
        hearing.set { _ in heard.map { !ignores && panel.pressed.count % 2 == 1 ? !$0 : $0 } }
        return PanelWay(setup: stale, remembered: nil, store: MemorySetupStore(), panel: panel, processIdentifier: { 4242 },
                        shown: { _ in PanelWay.Shown(titles: [], otherApps: ["Finder"], holdsNowPlaying: false) }, hearing: hearing,
                        sleep: { _ in })
    }

    @Test("a row that doesn't follow the app: its presses are checked by its sound")
    func staleRowChecked() {
        #expect(staleWay(FakePanel(shownPaused), heard: true).checksItsPresses)
    }

    @Test("a row that doesn't follow the app is pressed as a toggle only when its sound says it isn't as wanted yet")
    func staleRow() async throws {
        let playing = FakePanel(shownPaused)
        try await staleWay(playing, heard: true).pause()
        #expect(playing.pressed == ["Jukebox,  – "])
        let paused = FakePanel(shownPaused)
        try await staleWay(paused, heard: false).pause()
        #expect(paused.pressed.isEmpty)
        try await staleWay(paused, heard: false).play()
        #expect(paused.pressed == ["Jukebox,  – "])
        let playingAlready = FakePanel(shownPaused)
        try await staleWay(playingAlready, heard: true).play()
        #expect(playingAlready.pressed.isEmpty)
    }

    @Test("a row that doesn't follow the app is never pressed twice: a press its sound doesn't follow is an error")
    func staleRowNotPressedTwice() async {
        // Never heard to pause: a second press would undo a late first one.
        let ignored = FakePanel(shownPaused)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await staleWay(ignored, heard: true, ignores: true).pause() }
        #expect(ignored.pressed.count == 1)
    }

    @Test("a row that doesn't follow the app, unheard, says why it isn't pressed")
    func staleRowUnheard() async {
        await #expect(throws: MusicPlayerError.playerCommandFailed(.hearingUnavailable)) {
            try await staleWay(FakePanel(shownPaused), heard: nil).pause()
        }
    }

    @Test("else the row it changed with before")
    func remembered() async throws {
        let panel = FakePanel([PanelRow(text: "Other Song, Someone – Else", playing: false)])
        try await way(panel, store: MemorySetupStore(), titles: [], remembered: "Other Song, Someone – Else").play()
        #expect(panel.pressed == ["Other Song, Someone – Else"])
    }

    @Test("its row told by what it plays by AppleScript, where its check found it says")
    func toldByScript() async throws {
        let panel = FakePanel(rows)
        let way = PanelWay(setup: setup, remembered: nil, store: MemorySetupStore(), panel: panel, processIdentifier: { 4242 },
                           shown: { _ in PanelWay.Shown(titles: ["Jukebox"], track: "Song", otherApps: ["Finder"], holdsNowPlaying: false) })
        try await way.pause()
        #expect(panel.pressed == ["Song, Artist – Album"] && panel.openings == 1)
    }

    @Test("its page's player bar, where its check found its song there: read only when nothing else told its row, then the panel opened again")
    func toldByPlayerBar() async throws {
        let reads = Locked(0) // how many times the player bar was read
        func way(_ panel: FakePanel, titles: [String], bar: [String]) -> PanelWay {
            PanelWay(setup: setup, remembered: nil, store: MemorySetupStore(), panel: panel, processIdentifier: { 4242 },
                     shown: { _ in PanelWay.Shown(titles: titles, otherApps: ["Finder"], holdsNowPlaying: false) },
                     playerBar: { _ in
                         reads.increment()
                         return bar
                     })
        }
        let byBar = FakePanel(rows)
        try await way(byBar, titles: ["Jukebox"], bar: ["Song", "Artist", "Pause"]).pause()
        #expect(byBar.pressed == ["Song, Artist – Album"] && byBar.openings == 2 && reads.value == 1)
        let byTitle = FakePanel(rows)
        try await way(byTitle, titles: ["Song – Artist"], bar: ["Other Song"]).pause()
        #expect(byTitle.pressed == ["Song, Artist – Album"] && byTitle.openings == 1 && reads.value == 1) // not read
        // Nothing tells it, nor does the bar: not opened again.
        let none = FakePanel(rows)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) {
            try await way(none, titles: ["Jukebox"], bar: []).pause()
        }
        #expect(none.pressed.isEmpty && none.openings == 1 && reads.value == 2)
    }

    @Test("a remembered row, kept without its times, tells its row while it shows them, before its player bar is read")
    func rememberedWithTimes() async throws {
        let panel = FakePanel([PanelRow(text: "Other Song, Someone – Else 04:39 −05:21", playing: true)])
        let reads = Locked(0)
        let way = PanelWay(setup: setup, remembered: "Other Song, Someone – Else", store: MemorySetupStore(), panel: panel,
                           processIdentifier: { 4242 },
                           shown: { _ in PanelWay.Shown(titles: ["Jukebox"], otherApps: ["Finder"], holdsNowPlaying: false) },
                           playerBar: { _ in
                               reads.increment()
                               return []
                           })
        try await way.pause()
        #expect(panel.pressed == ["Other Song, Someone – Else 04:39 −05:21"] && panel.openings == 1 && reads.value == 0)
    }

    @Test("the only row playing while it holds Now Playing is pressed once its player bar, read first, didn't tell another")
    func onlyPlayingAfterPlayerBar() async throws {
        let panel = FakePanel([PanelRow(text: "Something, Else – Entirely", playing: true)])
        let way = PanelWay(setup: setup, remembered: nil, store: MemorySetupStore(), panel: panel, processIdentifier: { 4242 },
                           shown: { _ in PanelWay.Shown(titles: ["Jukebox"], otherApps: ["Finder"], holdsNowPlaying: true) },
                           playerBar: { _ in [] })
        try await way.pause()
        #expect(panel.pressed == ["Something, Else – Entirely"] && panel.openings == 2)
        // Without the bar to read, at once, as before.
        let once = FakePanel([PanelRow(text: "Something, Else – Entirely", playing: true)])
        try await PanelWay(setup: setup, remembered: nil, store: MemorySetupStore(), panel: once, processIdentifier: { 4242 },
                           shown: { _ in PanelWay.Shown(titles: ["Jukebox"], otherApps: ["Finder"], holdsNowPlaying: true) }).pause()
        #expect(once.pressed == ["Something, Else – Entirely"] && once.openings == 1)
    }

    @Test("a quiet pause (pressed again while AutoHush mutes the app) never shows the Now Playing panel; a plain pause does")
    func quietPauseSkipsPanel() async throws {
        let panel = FakePanel(rows)
        let player = CheckedPlayer(setup: setup, parts: .init(ways: [way(panel, store: MemorySetupStore())], signs: []), reports: nil,
                                   processIdentifier: { 4242 }, pressSleep: { _ in }, audioRecordingAllowed: { true })
        await #expect(throws: (any Error).self) { try await player.pauseQuietly() }
        #expect(panel.pressed.isEmpty)
        try await player.pause()
        #expect(panel.pressed == ["Song, Artist – Album"])
    }
}
