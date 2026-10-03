import Testing
@testable import AutoHush

@Suite("AppHealthState")
struct AppHealthStateTests {
    @Test("denied Automation needs permission")
    func automationDenied() {
        #expect(AppHealthState(startupError: AutoHushError.automationPermissionDenied)
            == .needsPermission("Grant Automation access to control Spotify"))
    }

    @Test("Spotify not running is degraded")
    func spotifyUnavailable() {
        #expect(AppHealthState(startupError: AutoHushError.spotifyUnavailable)
            == .degraded("Spotify is not running"))
    }

    @Test("an unresponsive Spotify is degraded")
    func spotifyNotResponding() {
        #expect(AppHealthState(startupError: AutoHushError.spotifyNotResponding)
            == .degraded("Spotify is not responding"))
    }

    @Test("a failed Spotify command is degraded with its message")
    func commandFailed() {
        #expect(AppHealthState(startupError: AutoHushError.spotifyCommandFailed("OSStatus -1712"))
            == .degraded("Spotify control error: OSStatus -1712"))
    }

    @Test("any other error fails with its description")
    func otherError() {
        #expect(AppHealthState(startupError: StubError.failed) == .failed("stub failed"))
    }
}
