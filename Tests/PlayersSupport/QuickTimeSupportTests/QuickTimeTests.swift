import Foundation
import Testing
import AutoHushKit
@testable import ScriptablePlayers
@testable import QuickTimeSupport

@Suite("QuickTime Player")
struct QuickTimeTests {
    @Test("QuickTime Player is named, identified, and scripted on its documents as its dictionary says, fading by each one's audio volume")
    func player() throws {
        let quickTime = QuickTime.player()
        #expect(quickTime.name == "QuickTime Player")
        #expect(quickTime.bundleID == "com.apple.QuickTimePlayerX")
        #expect(quickTime.iconPlaceholder != nil)
        // The setup a check would find in the QuickTime Player on every Mac, which can't say its documents' volume.
        let app = URL(fileURLWithPath: "/System/Applications/QuickTime Player.app")
        try #require(FileManager.default.fileExists(atPath: app.path))
        let dictionary = try #require(ScriptingDictionary.read(appAt: app, isRunning: false))
        var found = try #require(ScriptSetup(dictionary: dictionary))
        found.documentVolume = "volu"
        #expect(quickTime.setup == found)
        #expect(quickTime.canFade)
    }
}
