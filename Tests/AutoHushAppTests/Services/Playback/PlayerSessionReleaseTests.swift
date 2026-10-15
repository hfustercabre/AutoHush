import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// A player that turns something on in its app to be controlled (an added
/// app's page switch, a mute), counting the times it's turned back off.
private actor ReleasingPlayer: MusicPlayer {
    nonisolated let bundleID = "com.example.added"
    nonisolated let name = "Added"
    private let inner = MockMusicPlayer(bundleID: "com.example.added", name: "Added")
    private(set) var releases = 0

    nonisolated var releasesOnQuit: Bool { true }
    nonisolated var stateReportDelay: TimeInterval { 0 }
    nonisolated var volumeCurve: VolumeCurve { .linear }
    nonisolated var canFade: Bool { false }

    func verifyControlAccess() async throws {}
    func playerState() async -> PlayerState { await inner.playerState() }
    func pause() async throws { try await inner.pause() }
    func play() async throws { try await inner.play() }
    func volume() async -> Int? { nil }
    func setVolume(_ volume: Int) async throws {}
    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        inner.makeStateObserver(onChange: onChange)
    }
    func release() async { releases += 1 }
}

@MainActor
@Suite("PlayerSession: a player no longer chosen", .timeLimit(.minutes(1)))
struct PlayerSessionReleaseTests {
    private let added = ReleasingPlayer()
    private let other = MockMusicPlayer(bundleID: "com.example.other", name: "Other")
    private let monitorings = FakeMonitorings()

    private func session() async -> PlayerSession {
        let session = PlayerSession(
            player: added,
            players: MusicPlayerCatalog(players: [added, other]),
            preferences: Preferences(store: InMemoryPreferenceStore()),
            settings: MonitoringSettings(autoPause: true, ignored: [], timings: TimingSettings(), detection: .audioLevels),
            makeMonitoring: monitorings.make,
            locateApp: { URL(fileURLWithPath: "/Applications/\($0).app") }
        )
        session.launch()
        await TestWait.until { session.state.health == .ready }
        return session
    }

    @Test("what it turned on in its app goes back off once another is chosen")
    func released() async {
        let session = await session()
        session.choose(other)
        await TestWait.until { await added.releases == 1 }
        // Chosen again, then another: once more.
        session.choose(added)
        session.choose(other)
        await TestWait.until { await added.releases == 2 }
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
    }
}
