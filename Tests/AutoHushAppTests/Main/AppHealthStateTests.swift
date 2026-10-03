import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("AppHealthState")
struct AppHealthStateTests {
    private func health(_ error: any Error) -> AppHealthState {
        AppHealthState(startupError: error, playerName: "Spotify")
    }

    @Test("denied Automation needs permission")
    func automationDenied() {
        #expect(health(MusicPlayerError.automationPermissionDenied)
            == .needsPermission("Grant Automation access to control Spotify"))
    }

    @Test("a player that isn't running is degraded")
    func playerNotRunning() {
        #expect(health(MusicPlayerError.playerNotRunning) == .degraded("Spotify is not running"))
    }

    @Test("an unresponsive player is degraded")
    func playerNotResponding() {
        #expect(health(MusicPlayerError.playerNotResponding) == .degraded("Spotify is not responding"))
    }

    @Test("a failed player command is degraded with its message")
    func commandFailed() {
        #expect(health(MusicPlayerError.playerCommandFailed("OSStatus -50"))
            == .degraded("Spotify control error: OSStatus -50"))
    }

    @Test("messages name the player")
    func namesThePlayer() {
        #expect(AppHealthState(startupError: MusicPlayerError.playerNotRunning, playerName: "Music")
            == .degraded("Music is not running"))
    }

    @Test("any other error fails with its description")
    func otherError() {
        #expect(health(StubError.failed) == .failed("stub failed"))
    }
}
