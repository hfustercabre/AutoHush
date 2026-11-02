import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("PlayerSignals")
@MainActor
struct PlayerSignalsTests {
    private let music = Self.app("com.example.music", "Music")
    private let streamer = Self.app("com.example.streamer", "Streamer")
    private let radio = Self.app("com.example.radio", "Radio")

    @Test("the one playing or in Now Playing is picked, even with others open")
    func playing() {
        let signals = PlayerSignals(playing: [streamer.bundleID], open: [music.bundleID, streamer.bundleID])
        #expect(signals.likelyPlayer(among: [music, streamer, radio]) == streamer.bundleID)
    }

    @Test("with none playing, the one open is picked; with two open, none, as neither is likelier")
    func open() {
        #expect(PlayerSignals(open: [radio.bundleID]).likelyPlayer(among: [music, streamer, radio]) == radio.bundleID)
        #expect(PlayerSignals(open: [music.bundleID, radio.bundleID]).likelyPlayer(among: [music, streamer, radio]) == nil)
    }

    @Test("with two playing, none is picked: the one open or installed can't tell them apart either")
    func twoPlaying() {
        let both: Set = [music.bundleID, streamer.bundleID]
        #expect(PlayerSignals(playing: both, open: both).likelyPlayer(among: [music, streamer]) == nil)
    }

    @Test("with none open, the only supported app installed is picked; with two installed, none: today's window")
    func onlyInstalled() {
        let missing = PlayerOption(bundleID: radio.bundleID, name: "Radio", appURL: nil)
        #expect(PlayerSignals().likelyPlayer(among: [music, missing]) == music.bundleID)
        #expect(PlayerSignals().likelyPlayer(among: [music, streamer]) == nil)
        #expect(PlayerSignals().likelyPlayer(among: []) == nil)
    }

    @Test("never a Safari web app (added or suggested, tested or not), an added app, or one AntiDot mode keeps from being chosen")
    func onlySupportedApps() {
        var webApp = PlayerOption(bundleID: "com.apple.Safari.WebApp.1", name: "Yodel",
                                  appURL: URL(fileURLWithPath: "/Applications/Yodel.app"), kind: .safariWebApp)
        webApp.isUntested = true
        let suggested = PlayerOption.suggestion(WebAppSuggestion(name: "Tunes", address: "tunes.example.com"))
        let added = PlayerOption(bundleID: "com.example.added", name: "Added",
                                 appURL: URL(fileURLWithPath: "/Applications/Added.app"), kind: .checkedApp)
        var mutedOnly = streamer
        mutedOnly.isUnavailableInAntiDotMode = true
        let everyone: Set = [webApp.bundleID, suggested.bundleID, added.bundleID, mutedOnly.bundleID]

        // Playing, open, and the only ones there: still not picked.
        let signals = PlayerSignals(playing: everyone, open: everyone)
        #expect(signals.likelyPlayer(among: [webApp, suggested, added, mutedOnly]) == nil)
        // Nor do they stand in the way of the one supported app.
        #expect(signals.likelyPlayer(among: [music, webApp, suggested, added, mutedOnly]) == music.bundleID)
        #expect(PlayerSignals().likelyPlayer(among: [music, webApp, suggested, added]) == music.bundleID)
    }

    @Test("a player playing but not offered (not installed) isn't picked: the next signal decides")
    func playingButNotOffered() {
        let missing = PlayerOption(bundleID: radio.bundleID, name: "Radio", appURL: nil)
        let signals = PlayerSignals(playing: [radio.bundleID], open: [radio.bundleID, music.bundleID])
        #expect(signals.likelyPlayer(among: [music, streamer, missing]) == music.bundleID)
    }

    private static func app(_ bundleID: String, _ name: String) -> PlayerOption {
        PlayerOption(bundleID: bundleID, name: name, appURL: URL(fileURLWithPath: "/Applications/\(name).app"))
    }
}
