import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerSession", .waitsTimeLimit)
struct PlayerSessionTests {
    typealias Players = TestPlayers

    static let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    static let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
    static let settings = MonitoringSettings(autoPause: true, ignored: [], timings: TimingSettings(),
                                             detection: .audioLevels)

    /// In-memory preferences, two stand-in players that may be controlled
    /// (a test refuses it with `setFailVerify`), both installed, and
    /// monitorings that stand in for the engine.
    @MainActor
    final class Bench {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let first = MockMusicPlayer(bundleID: Players.first, name: "First")
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second")
        lazy var players = MusicPlayerCatalog(players: [first, second], formerDefault: Players.first)
        var installed: Set<String> = [Players.first, Players.second]
        let monitorings = FakeMonitorings()
        /// The waits between startup checks, each over once the test steps it.
        let startupWaits = ManualSleep()
        /// The states a session told, in order, once `record` is called.
        var changes: [PlayerSession.State] = []

        func record(_ session: PlayerSession) {
            session.didChange = { [weak self] in self?.changes.append($0) }
        }

        func makeSession(_ chosen: any MusicPlayer?) -> PlayerSession {
            PlayerSession(
                player: chosen,
                players: players,
                preferences: preferences,
                settings: PlayerSessionTests.settings,
                makeMonitoring: monitorings.make,
                // Weak: a session may still be retrying a start once its test is over.
                locateApp: { [weak self] id in
                    self?.installed.contains(id) == true ? URL(fileURLWithPath: "/Applications/\(id).app") : nil
                },
                retries: PlayerSession.Retries(permissionInterval: 0.05, delays: 0.02...0.08, startupWait: startupWaits.sleep)
            )
        }

        /// A session monitoring the first player, ready.
        func started() async -> PlayerSession {
            let session = makeSession(first)
            session.launch()
            await TestWait.until { session.state.health == .ready }
            return session
        }

        /// A session with the second player chosen, found not running as it
        /// launched, done starting.
        func secondNotRunning() async -> PlayerSession {
            await second.setFailVerify(MusicPlayerError.playerNotRunning)
            let session = makeSession(second)
            session.launch()
            await TestWait.until { session.state.health != .starting }
            await session.waitUntilIdle()
            return session
        }

        /// The first player chosen, monitored and paused by AutoHush, then
        /// the second chosen: the first's pause is held.
        func holdingFirst() async -> PlayerSession {
            let session = await started()
            monitorings.made[0].send(.playback(.pausedByMonitor))
            session.choose(second)
            await TestWait.until { session.state.health == .ready && !self.monitorings.of(Players.second).isEmpty }
            return session
        }
    }
}
