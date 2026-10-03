import Testing
@testable import AutoHush

@Suite("AutoHushError")
struct AutoHushErrorTests {

    @Test("automationPermissionDenied has a human-readable description")
    func automationPermissionDeniedDescription() {
        let error = AutoHushError.automationPermissionDenied
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("automation"))
    }

    @Test("playerNotRunning has a human-readable description")
    func spotifyUnavailableDescription() {
        let error = AutoHushError.playerNotRunning
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("player"))
    }

    @Test("playerCommandFailed surfaces the provided message")
    func spotifyCommandFailedDescription() {
        let error = AutoHushError.playerCommandFailed("OSStatus -1712")
        #expect(error.errorDescription?.contains("OSStatus -1712") == true)
    }

    @Test("playerCommandFailed with empty message still produces a description")
    func spotifyCommandFailedEmptyMessage() {
        let error = AutoHushError.playerCommandFailed("")
        #expect(error.errorDescription?.isEmpty == false)
    }
}
