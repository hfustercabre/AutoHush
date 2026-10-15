import Foundation
import Testing
@testable import MenuPlayers
import AutoHushKit

@Suite("PlayPauseWords of any app")
struct PlayPauseWordsTests {
    @Test("the common words: lowercase and capitalized, in a few languages")
    func common() {
        #expect(PlayPauseWords.common.play.isSuperset(of: ["play", "Play", "Reproducir", "reprodueix"]))
        #expect(PlayPauseWords.common.pause.isSuperset(of: ["pause", "Pause", "Pausa", "posa en pausa"]))
        #expect(MenuPlayer.state(of: MenuToggle(title: "Pause", isEnabled: true), words: .common) == .playing)
        #expect(MenuPlayer.state(of: MenuToggle(title: "Reproducir", isEnabled: true), words: .common) == .paused)
    }

    @Test("an app's own words: every language of a table whose English is Play or Pause, with where they came from")
    func found() throws {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Words-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: app) }
        func strings(_ language: String, _ table: [String: String]) throws {
            let folder = app.appendingPathComponent("Contents/Resources/\(language).lproj")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect((table as NSDictionary).write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true))
        }
        try strings("en", ["toggle.play": "Play", "toggle.pause": "Pause", "other": "Open"])
        try strings("ca", ["toggle.play": "Reprodueix", "toggle.pause": "Posa en pausa", "other": "Obre"])
        let found = try #require(PlayPauseWords.found(inAppAt: app))
        #expect(found.words.play == ["Play", "Reprodueix"])
        #expect(found.words.pause == ["Pause", "Posa en pausa"])
        #expect(found.source == "en.lproj/Localizable.strings")

        let merged = PlayPauseWords.common.merged(with: found.words)
        #expect(merged.play.contains("Reprodueix") && merged.play.contains("lecture"))
        #expect(PlayPauseWords.found(inAppAt: app.appendingPathComponent("missing")) == nil)
    }

    @Test("an app added through a check reads its words with the common ones")
    func profile() throws {
        let profile = MenuPlayerProfile.found(bundleID: "com.example.jukebox", name: "Jukebox", menuName: "Play")
        let words = try #require(profile.readWords(URL(fileURLWithPath: "/nonexistent.app")))
        #expect(words == .common)
    }
}
