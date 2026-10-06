import Foundation
import Testing
import AutoHushKit
import MenuPlayers
@testable import PodcastsSupport

@Suite("Apple Podcasts")
struct PodcastsTests {
    @Test("Apple Podcasts is controlled through its Controls menu")
    func profile() {
        let podcasts = MenuPlayer(profile: .applePodcasts)
        #expect(podcasts.name == "Apple Podcasts")
        #expect(podcasts.bundleID == "com.apple.podcasts")
        #expect(podcasts.profile.menuName == "Controls")
        #expect(podcasts.controlPermission == .accessibility(player: "Apple Podcasts"))
        #expect(!podcasts.canFade)
    }

    @Test("the words are the texts whose English is Play or Pause, in every language")
    func wordsFromTable() throws {
        let table: [String: Any] = [
            "en": ["Play": "Play", "PLAY_BUTTON_PAUSE": "Pause", "AX_PAUSE": "Pause", "Shuffle": "Shuffle",
                   "EPISODES": ["NSStringLocalizedFormatKey": "%#@n@"]],
            "de": ["Play": "Wiedergabe", "PLAY_BUTTON_PAUSE": "Pause", "AX_PAUSE": "Pausieren", "Shuffle": "Zufällig"],
            "fr": ["Play": "Lire", "PLAY_BUTTON_PAUSE": "Pause"],
            "LocProvenance": ["de": "1234"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
        let words = try #require(PodcastsWords.find(in: data))
        #expect(words.play == ["Play", "Wiedergabe", "Lire"])
        #expect(words.pause == ["Pause", "Pausieren"])
        #expect(PodcastsWords.find(in: Data("not a table".utf8)) == nil)
    }

    @Test("the Podcasts app that comes with macOS has words for both, none shared")
    func installedWords() throws {
        let app = URL(fileURLWithPath: "/System/Applications/Podcasts.app")
        try #require(FileManager.default.fileExists(atPath: app.path))
        let words = try #require(PodcastsWords.read(fromAppAt: app))
        #expect(words.play.contains("Play") && words.pause.contains("Pause"))
        #expect(words.play.isDisjoint(with: words.pause))
    }
}
