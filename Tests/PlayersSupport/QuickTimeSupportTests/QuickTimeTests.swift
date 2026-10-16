import Foundation
import Testing
import AutoHushKit
import ScriptablePlayers
@testable import QuickTimeSupport

@Suite("QuickTime Player")
struct QuickTimeTests {
    @Test("QuickTime Player is named, identified, and scripted on its documents, without fades")
    func player() {
        let quickTime = QuickTime.player()
        #expect(quickTime.name == "QuickTime Player")
        #expect(quickTime.bundleID == "com.apple.QuickTimePlayerX")
        #expect(quickTime.iconPlaceholder != nil)
        #expect(quickTime.setup.commands == .pauseAndPlay(pause: "MVWRpaus", play: "MVWRplay"))
        #expect(quickTime.setup.actsOnDocuments)
        #expect(quickTime.setup.state == .documents(documentClass: "docu", playing: "play"))
        #expect(!quickTime.canFade)
    }
}
