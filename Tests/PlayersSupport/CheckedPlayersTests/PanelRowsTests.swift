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

    @Test("as a toggle, the app's own row is pressed whatever it shows, and never the only one playing")
    func asToggle() {
        let rows = [PanelRow(text: "Qobuz,  – ", playing: false), PanelRow(text: "Song, Artist – Album", playing: true)]
        let own = PanelRows.row(in: rows, pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil, holdsNowPlaying: true, asToggle: true)
        #expect(own == rows[0])
        // Not as a toggle, its row showing paused isn't one to press to pause it.
        #expect(PanelRows.row(in: rows, pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil, holdsNowPlaying: false) == nil)
        #expect(PanelRows.row(in: [rows[1]], pausing: true, appName: "Qobuz", otherApps: [], texts: [], remembered: nil, holdsNowPlaying: true,
                              asToggle: true) == nil)
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

    @Test("macOS 14's panel: a row is a text and the button after it, saying Pause while it plays, in Control Center's words; Next and a button with no text before it aren't rows")
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
