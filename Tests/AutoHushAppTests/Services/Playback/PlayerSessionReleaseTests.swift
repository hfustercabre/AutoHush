import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@MainActor
@Suite("PlayerSession: a player no longer chosen", .timeLimit(.minutes(1)))
struct PlayerSessionReleaseTests {
    /// A player that turns something on in its app to be controlled (an
    /// added app's page switch, a mute), counting the times it's turned back off.
    private let added = MockMusicPlayer(bundleID: "com.example.added", name: "Added", canFade: false, releasesOnQuit: true)
    private let other = MockMusicPlayer(bundleID: "com.example.other", name: "Other")
    private let monitorings = FakeMonitorings()

    /// A session with the added app chosen, not started yet.
    private func makeSession() -> PlayerSession {
        PlayerSession(
            player: added,
            players: MusicPlayerCatalog(players: [added, other]),
            preferences: Preferences(store: InMemoryPreferenceStore()),
            settings: MonitoringSettings(autoPause: true, ignored: [], timings: TimingSettings(), detection: .audioLevels),
            makeMonitoring: monitorings.make,
            locateApp: { URL(fileURLWithPath: "/Applications/\($0).app") }
        )
    }

    private func session() async -> PlayerSession {
        let session = makeSession()
        session.launch()
        await TestWait.until { session.state.health == .ready }
        return session
    }

    @Test("what it turned on in its app goes back off once another is chosen, and as AutoHush quits, monitored or not")
    func released() async {
        let session = await session()
        session.choose(other)
        await TestWait.until { await added.releases == 1 }
        #expect(await added.releases == 1)
        // Chosen again, then another: once more.
        session.choose(added)
        session.choose(other)
        await TestWait.until { await added.releases == 2 }
        #expect(await added.releases == 2)

        // Chosen again and monitored, then AutoHush quits.
        session.choose(added)
        await TestWait.until { session.state.health == .ready }
        await session.quit()?.value
        #expect(await added.releases == 3)

        // Quitting before it was ever monitored.
        let quitting = makeSession().quit()
        #expect(quitting != nil)
        await quitting?.value
        #expect(await added.releases == 4)
    }

    @Test("with its pause held, only once that pause is over")
    func releasedAfterItsPause() async {
        let session = await session()
        monitorings.made[0].send(.playback(.pausedByMonitor))
        session.choose(other)
        await TestWait.until { session.isHoldingPause }
        #expect(await added.releases == 0)
        monitorings.made[0].send(.playback(.musicPlaying))
        await TestWait.until { await added.releases == 1 }
        #expect(await added.releases == 1)
    }
}
