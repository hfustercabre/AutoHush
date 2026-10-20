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

    /// Where an app keeps its translations, as the source names it.
    enum Translations: String, CaseIterable {
        case strings = "en.lproj/Localizable.strings"
        case loctable = "Localizable.loctable"
        case asar = "app.asar"

        func write(in resources: URL) throws {
            let english = ["toggle.play": "Play", "toggle.pause": "Pause", "other": "Open"]
            let catalan = ["toggle.play": "Reprodueix", "toggle.pause": "Posa en pausa", "other": "Obre"]
            switch self {
            case .strings:
                for (language, table) in [("en", english), ("ca", catalan)] {
                    let folder = resources.appendingPathComponent("\(language).lproj")
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    #expect((table as NSDictionary).write(to: folder.appendingPathComponent("Localizable.strings"), atomically: true))
                }
            case .loctable:
                try PropertyListSerialization.data(fromPropertyList: ["en": english, "ca": catalan], format: .binary, options: 0)
                    .write(to: resources.appendingPathComponent(rawValue))
            case .asar:
                // Its header, then each language's JSON (TIDAL's "t-play"): a
                // "Play" that's no key's text, an escaped letter, and spaces
                // around a colon.
                let files = #"""
                    {"files":{"locales":{"files":{"en.json":{},"ca.json":{}}}}}
                    {"t-play": "Play", "t-pause" : "Pause", "other": "Open", "shortcuts": ["Play"]}
                    {"t-play":"Reprodu\u0065ix","t-pause" :	"Posa en pausa","other":"Obre"}
                    """#
                try (Data([4, 0, 0, 0]) + Data(files.utf8)).write(to: resources.appendingPathComponent(rawValue))
            }
        }
    }

    /// An app of its own whose resources hold `translations`; the caller removes it.
    private func makeApp(with translations: Translations) throws -> URL {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent("Words-\(UUID().uuidString).app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try translations.write(in: resources)
        return app
    }

    @Test("an app's own words: every language of a table whose English is Play or Pause (folders, .loctable, app.asar), and where from",
          arguments: Translations.allCases)
    func found(_ translations: Translations) throws {
        let app = try makeApp(with: translations)
        defer { try? FileManager.default.removeItem(at: app) }
        let found = try #require(PlayPauseWords.found(inAppAt: app))
        #expect(found.words.play == ["Play", "Reprodueix"])
        #expect(found.words.pause == ["Pause", "Posa en pausa"])
        #expect(found.source == translations.rawValue)
    }

    @Test("an app's own words add to the common ones", arguments: Translations.allCases)
    func merged(_ translations: Translations) throws {
        let app = try makeApp(with: translations)
        defer { try? FileManager.default.removeItem(at: app) }
        let found = try #require(PlayPauseWords.found(inAppAt: app))
        let merged = PlayPauseWords.common.merged(with: found.words)
        #expect(merged.play.contains("Reprodueix") && merged.play.contains("lecture"))
    }

    @Test("an app that isn't there has no words of its own")
    func missing() {
        #expect(PlayPauseWords.found(inAppAt: URL(fileURLWithPath: "/nonexistent/Words.app")) == nil)
    }

    @Test("an app added through a check reads its words with the common ones")
    func profile() throws {
        let profile = MenuPlayerProfile.found(bundleID: "com.example.jukebox", name: "Jukebox", menuName: "Play")
        let words = try #require(profile.readWords(URL(fileURLWithPath: "/nonexistent.app")))
        #expect(words == .common)
    }
}
