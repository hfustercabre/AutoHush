import Foundation
import Testing
import AutoHushKit
import ScriptablePlayers
@testable import AppleMusicSupport

@Suite("Apple Music")
struct AppleMusicTests {
    @Test("Apple Music is named, identified and scripted through the Music suite")
    func profile() {
        let music = ScriptablePlayerProfile.appleMusic
        #expect(music.name == "Apple Music")
        #expect(music.bundleID == "com.apple.Music")
        #expect(music.suite == fourCharCode("hook"))
        #expect(music.stateNotification.rawValue == "com.apple.Music.playerInfo")
    }
}
