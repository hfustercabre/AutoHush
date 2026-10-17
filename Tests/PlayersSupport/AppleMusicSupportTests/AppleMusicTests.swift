import Foundation
import Testing
import ScriptablePlayers
@testable import AppleMusicSupport

@Suite("Apple Music")
struct AppleMusicTests {
    @Test("Apple Music is named, identified and scripted through the Music suite, as the Music app's dictionary has it")
    func profile() throws {
        let music = ScriptablePlayerProfile.appleMusic
        #expect(music.name == "Apple Music")
        #expect(music.bundleID == "com.apple.Music")
        #expect(music.suite == fourCharCode("hook"))
        #expect(music.stateNotification.rawValue == "com.apple.Music.playerInfo")
        // The Music app on every Mac: pause and play in that suite, and a player state.
        let app = URL(fileURLWithPath: "/System/Applications/Music.app")
        try #require(FileManager.default.fileExists(atPath: app.path))
        let dictionary = try #require(ScriptingDictionary.read(appAt: app, isRunning: false))
        #expect(dictionary.suite == "hook")
        #expect(dictionary.fitsScriptablePlayer)
    }
}
