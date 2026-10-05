import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("MusicPlayerError")
struct MusicPlayerErrorTests {

    @Test("automationPermissionDenied has a human-readable description")
    func automationPermissionDeniedDescription() {
        let error = MusicPlayerError.automationPermissionDenied
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("automation"))
    }

    @Test("playerNotRunning has a human-readable description")
    func playerUnavailableDescription() {
        let error = MusicPlayerError.playerNotRunning
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("player"))
    }

    @Test("playerCommandFailed surfaces the provided message")
    func playerCommandFailedDescription() {
        let error = MusicPlayerError.playerCommandFailed("OSStatus -1712")
        #expect(error.errorDescription?.contains("OSStatus -1712") == true)
    }

    @Test("playerCommandFailed with empty message still produces a description")
    func playerCommandFailedEmptyMessage() {
        let error = MusicPlayerError.playerCommandFailed("")
        #expect(error.errorDescription?.isEmpty == false)
    }
}
