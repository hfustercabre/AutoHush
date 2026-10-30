import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport

/// A player that opts into both: no volume, read now and then.
private struct MenuLikePlayer: FadelessMusicPlayer, PolledMusicPlayer {
    let bundleID = "com.example.menu"
    let name = "Menu"
    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { .paused }
    func pause() async throws {}
    func play() async throws {}
}

/// One that opts into neither, but says how late it reports.
private struct ScriptedLikePlayer: MusicPlayer {
    let bundleID = "com.example.scripted"
    let name = "Scripted"
    let stateReportDelay: TimeInterval = 0
    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { .paused }
    func pause() async throws {}
    func play() async throws {}
    func volume() async -> Int? { 50 }
    func setVolume(_ volume: Int) async throws {}
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { .paused }, onChange: onChange)
    }
}

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
