import Foundation
import Testing
@testable import AutoHushApp

@MainActor
private final class FakeMonitoring: StoppableMonitoring {
    private(set) var stops = 0
    func stop() { stops += 1 }
}

@Suite("HeldPauses")
@MainActor
struct HeldPausesTests {
    @Test("a held pause's monitoring runs on while its player is paused by it, and stops once it plays again")
    func stopsOncePlaying() {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")

        #expect(held.follow(.playback(.pausedByMonitor), from: token)) // still holding it
        #expect(held.follow(.detection(.audioLevel), from: token))
        #expect(monitoring.stops == 0 && !held.isEmpty)

        #expect(held.follow(.playback(.musicPlaying), from: token)) // the other apps stopped: it plays again
        #expect(monitoring.stops == 1 && held.isEmpty)
        #expect(!held.follow(.playback(.musicPlaying), from: token)) // no longer kept
    }

    @Test("the user taking the player over stops it too; an unknown state doesn't")
    func stopsWhenTakenOver() {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")
        _ = held.follow(.playback(.unknown), from: token)
        #expect(monitoring.stops == 0)
        _ = held.follow(.playback(.musicIdle), from: token) // the user stopped or quit it
        #expect(monitoring.stops == 1)
    }

    @Test("updates of the current monitoring aren't taken; a player chosen again is taken back; sleep forgets them all")
    func currentTakeBackAndSleep() {
        let held = HeldPauses()
        let vlc = FakeMonitoring()
        let spotify = FakeMonitoring()
        held.keep(vlc, token: UUID(), bundleID: "org.videolan.vlc")
        held.keep(spotify, token: UUID(), bundleID: "com.spotify.client")
        #expect(!held.follow(.playback(.musicPlaying), from: UUID())) // the current one's

        #expect(held.takeBack("org.videolan.vlc"))
        #expect(vlc.stops == 1)
        #expect(!held.takeBack("org.videolan.vlc"))

        held.stopAll()
        #expect(spotify.stops == 1 && held.isEmpty)
    }
}
