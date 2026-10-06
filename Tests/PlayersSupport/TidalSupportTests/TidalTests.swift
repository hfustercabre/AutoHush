import Foundation
import Testing
import AutoHushKit
import MenuPlayers
@testable import TidalSupport

@Suite("TIDAL")
struct TidalTests {
    @Test("TIDAL is controlled through its Playback menu")
    func profile() {
        let tidal = MenuPlayer(profile: .tidal)
        #expect(tidal.name == "TIDAL")
        #expect(tidal.bundleID == "com.tidal.desktop")
        #expect(tidal.profile.menuName == "Playback")
        #expect(tidal.controlPermission == .accessibility(player: "TIDAL"))
        #expect(!tidal.canFade)
    }

    @Test("TIDAL's words for Play and Pause are found in every language, escapes decoded")
    func wordsFromTranslations() {
        let tables = #"""
        {"t-pause": "Pause", "t-play": "Play", "t-playback": "Playback"}
        …binary…{"t-pause": "Пауза","t-play":"Пусни"}
        {"t-play": "Lecture", "t-pause": "Pause"} "t-play": "Réproduire"
        """#
        let words = TidalWords.find(in: Data(tables.utf8))
        #expect(words.play == ["Play", "Пусни", "Lecture", "Re\u{301}produire"])
        #expect(words.pause == ["Pause", "Пауза"])
    }

    @Test("the words are read from the app.asar inside TIDAL's bundle")
    func wordsOfApp() throws {
        let app = FileManager.default.temporaryDirectory.appending(path: "TIDAL-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        let resources = app.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try Data(#"{"t-play": "Reproducir", "t-pause": "Pausa"}"#.utf8).write(to: resources.appending(path: "app.asar"))
        #expect(TidalWords.read(fromAppAt: app) == PlayPauseWords(play: ["Reproducir"], pause: ["Pausa"]))
        #expect(TidalWords.read(fromAppAt: app.deletingLastPathComponent()) == nil)
    }
}
