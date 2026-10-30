import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("MusicPlayer's defaults", .waitsTimeLimit)
struct MusicPlayerDefaultsTests {
    @Test("a fadeless player can't fade and has no volume; a polled one is read now and then, and says a change may come a read late")
    @MainActor
    func optedIn() async throws {
        let player = MenuLikePlayer()
        #expect(!player.canFade)
        #expect(await player.volume() == nil)
        try await player.setVolume(10)
        #expect(player.stateReportDelay == PolledStateObserver.reportDelay)
        #expect(player.makeStateObserver(onChange: { _ in }) is PolledStateObserver)
        // Seen as any player, as the engine sees it.
        let any: any MusicPlayer = player
        #expect(!any.canFade)
        #expect(any.stateReportDelay == PolledStateObserver.reportDelay)
    }

    @Test("a player that opts into neither keeps fading")
    func notOptedIn() {
        let any: any MusicPlayer = ScriptedLikePlayer()
        #expect(any.canFade)
        #expect(any.stateReportDelay == 0)
    }
}
