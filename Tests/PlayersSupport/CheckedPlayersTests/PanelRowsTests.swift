import Testing
@testable import CheckedPlayers

@Suite("PanelRows")
struct PanelRowsTests {
    private let rows = [
        PanelRow(text: "I Worry Too Much, Egotist – I Worry Too Much", playing: true),
        PanelRow(text: "Another One Bites The Dust, Queen – The Game", playing: false),
        PanelRow(text: "QuickTime Player", playing: true),
    ]

    @Test("a row's song: its text up to each comma before the album; the whole text without one")
    func songs() {
        #expect(PanelRows.songs(ofRow: "Song (Edit), Artist, Other – Album") == ["Song (Edit)", "Song (Edit), Artist"])
        #expect(PanelRows.songs(ofRow: "QuickTime Player") == ["QuickTime Player"])
        #expect(PanelRows.normalized("Song (Edit) - Artist") == "song edit artist")
    }

    @Test("the app's row shows its song, found whole in what it shows, or its name; never a word in common")
    func appRows() {
        let spotify = PanelRows.appRows(rows, appName: "Spotify", otherApps: ["QuickTime Player"],
                                        texts: ["I Worry Too Much — Egotist"])
        #expect(spotify.map(\.text) == ["I Worry Too Much, Egotist – I Worry Too Much"])
        let quickTime = PanelRows.appRows(rows, appName: "QuickTime Player", otherApps: [], texts: [])
        #expect(quickTime.map(\.text) == ["QuickTime Player"])
        // "the" alone isn't SoundCloud's song.
        #expect(PanelRows.appRows(rows, appName: "SoundCloud", otherApps: [], texts: ["the"]).isEmpty)
        // Another app's name isn't this app's song.
        #expect(PanelRows.appRows(rows, appName: "VLC", otherApps: ["QuickTime Player"], texts: ["QuickTime Player"]).isEmpty)
    }

    /// Qobuz's own row, showing paused, and another app's playing.
    private let qobuzRows = [PanelRow(text: "Qobuz,  – ", playing: false), PanelRow(text: "Song, Artist – Album", playing: true)]

    @Test("as a toggle, the app's own row is pressed whatever it shows")
    func asToggle() {
        let own = PanelRows.row(in: qobuzRows, pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil, holdsNowPlaying: true,
                                asToggle: true)
        #expect(own == qobuzRows[0])
        // Not as a toggle, its row showing paused isn't one to press to pause it.
        #expect(PanelRows.row(in: qobuzRows, pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil,
                              holdsNowPlaying: false) == nil)
    }

    @Test("as a toggle, the only row playing isn't pressed")
    func asToggleNeverTheOnlyOnePlaying() {
        #expect(PanelRows.row(in: [qobuzRows[1]], pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil, holdsNowPlaying: true,
                              asToggle: true) == nil)
    }

    @Test("a row that doesn't follow its app is one while its sound says otherwise")
    func staleRow() {
        // Its row shows paused while it's heard (pausing), or playing while it's silent (playing it): stale.
        func stale(pausing: Bool, heard: Bool?) -> PanelRow? {
            PanelRows.staleRow(in: qobuzRows, pausing: pausing, heard: heard, appName: "Qobuz", otherApps: [], texts: [], remembered: nil)
        }
        #expect(stale(pausing: true, heard: true) == qobuzRows[0] && stale(pausing: false, heard: false) == qobuzRows[0])
        #expect(stale(pausing: true, heard: false) == nil && stale(pausing: false, heard: true) == nil && stale(pausing: true, heard: nil) == nil)
    }

    @Test("the row to press: its song's, else the one it changed with before, else the only one playing while it holds Now Playing")
    func row() {
        #expect(PanelRows.row(in: rows, pausing: false, appName: "Spotify", otherApps: [], texts: ["Another One Bites The Dust"],
                              remembered: nil, holdsNowPlaying: false)?.text == "Another One Bites The Dust, Queen – The Game")
        #expect(PanelRows.row(in: rows, pausing: false, appName: "Deezer", otherApps: [], texts: [],
                              remembered: "Another One Bites The Dust, Queen – The Game", holdsNowPlaying: false) != nil)
        let onePlaying = [PanelRow(text: "Some Song, Someone – Album", playing: true)]
        #expect(PanelRows.row(in: onePlaying, pausing: true, appName: "Deezer", otherApps: [], texts: [],
                              remembered: nil, holdsNowPlaying: true) == onePlaying[0])
        #expect(PanelRows.row(in: onePlaying, pausing: true, appName: "Deezer", otherApps: [], texts: [],
                              remembered: nil, holdsNowPlaying: false) == nil)
        // Two rows playing and nothing to tell them apart: none.
        #expect(PanelRows.row(in: onePlaying + [PanelRow(text: "Other, X – Y", playing: true)], pausing: true, appName: "Deezer",
                              otherApps: [], texts: [], remembered: nil, holdsNowPlaying: true) == nil)
        // Two rows showing its song (another app may play it too): none, not the one it changed with.
        let twice = [PanelRow(text: "Some Song, Someone – Album", playing: false), PanelRow(text: "Some Song, Someone – Live", playing: false)]
        #expect(PanelRows.row(in: twice, pausing: false, appName: "Deezer", otherApps: [], texts: ["Some Song — Someone"],
                              remembered: twice[0].text, holdsNowPlaying: false) == nil)
    }

    @Test("macOS 14's panel: a row is a text and the Play or Pause after it, telling whether it plays, in Control Center's words; nothing else is")
    func flatRows() {
        // Each element as its attributes.
        let children: [[String: String]] = [
            ["AXRole": "AXButton", "AXDescription": "Play"], // no text before it
            ["AXRole": "AXStaticText", "AXValue": "Some Song, Someone – Album"],
            ["AXRole": "AXButton", "AXDescription": "Pause"],
            ["AXRole": "AXButton", "AXDescription": "Next"],
            ["AXRole": "AXStaticText", "AXValue": "Other, Someone Else – Live"],
            ["AXRole": "AXImage"],
            ["AXRole": "AXButton", "AXDescription": "Reproducir"], // Control Center in Spanish
            ["AXRole": "AXButton", "AXDescription": "Siguiente"],
        ]
        let rows = AccessibilityNowPlayingPanel.flatRows(in: children, words: (play: ["play", "reproducir"], pause: ["pause", "pausa"])) { $0[$1] }
        #expect(rows.map { $0.row } == [PanelRow(text: "Some Song, Someone – Album", playing: true),
                                        PanelRow(text: "Other, Someone Else – Live", playing: false)])
        #expect(rows.map { $0.button["AXDescription"] } == ["Pause", "Reproducir"])
    }
}
