import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("PlayerChooserView")
@MainActor
struct PlayerChooserViewTests {
    private let music = PlayerOption(bundleID: "com.example.music", name: "Music", appURL: URL(fileURLWithPath: "/Applications/Music.app"))
    private let streamer = PlayerOption(bundleID: "com.example.streamer", name: "Streamer",
                                        appURL: URL(fileURLWithPath: "/Applications/Streamer.app"))

    @Test("the likely player starts picked, and follows the signals and the list until the user picks a tile, which it never overrides")
    func selection() {
        let options = [music, streamer]
        let playing = PlayerSignals(playing: [streamer.bundleID], open: [music.bundleID, streamer.bundleID])
        #expect(PlayerChooserView.selection(picked: nil, among: options, signals: PlayerSignals()) == nil) // two installed
        #expect(PlayerChooserView.selection(picked: nil, among: options, signals: PlayerSignals(open: [music.bundleID])) == music.bundleID)
        #expect(PlayerChooserView.selection(picked: nil, among: options, signals: playing) == streamer.bundleID) // read a moment later
        #expect(PlayerChooserView.selection(picked: nil, among: [music], signals: PlayerSignals()) == music.bundleID) // the list refreshed

        // A tile the user picked stays picked, whatever the signals say.
        #expect(PlayerChooserView.selection(picked: music.bundleID, among: options, signals: playing) == music.bundleID)
        // Unless it's no longer offered, or can't be chosen: the likely one then.
        let missing = PlayerOption(bundleID: music.bundleID, name: "Music", appURL: nil)
        #expect(PlayerChooserView.selection(picked: music.bundleID, among: [missing, streamer], signals: playing) == streamer.bundleID)
        #expect(PlayerChooserView.selection(picked: music.bundleID, among: [missing, streamer], signals: PlayerSignals()) == streamer.bundleID)
    }

    @Test("a double-click chooses the player on its tile; a suggested web app's does what its clicks do, and a tile that can't be chosen nothing")
    func doubleClick() {
        #expect(PlayerChooserView.doubleClickChoice(music) == music.bundleID)
        var added = PlayerOption(bundleID: "com.apple.Safari.WebApp.1", name: "Yodel",
                                 appURL: URL(fileURLWithPath: "/Applications/Yodel.app"), kind: .safariWebApp)
        added.isUntested = true
        #expect(PlayerChooserView.doubleClickChoice(added) == added.bundleID) // an added web app can be chosen
        let suggested = PlayerOption.suggestion(WebAppSuggestion(name: "Tunes", address: "tunes.example.com"))
        #expect(PlayerChooserView.doubleClickChoice(suggested) == nil) // its clicks opened Add a Web App
        #expect(PlayerChooserView.doubleClickChoice(PlayerOption(bundleID: "com.example.gone", name: "Gone", appURL: nil)) == nil)
        var mutedOnly = streamer
        mutedOnly.isUnavailableInAntiDotMode = true
        #expect(PlayerChooserView.doubleClickChoice(mutedOnly) == nil)
    }
}
