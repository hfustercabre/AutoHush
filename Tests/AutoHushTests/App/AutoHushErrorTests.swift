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

    @Test("spotifyUnavailable has a human-readable description")
    func spotifyUnavailableDescription() {
        let error = AutoHushError.spotifyUnavailable
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("spotify"))
    }

    @Test("spotifyCommandFailed surfaces the provided message")
    func spotifyCommandFailedDescription() {
        let error = AutoHushError.spotifyCommandFailed("OSStatus -1712")
        #expect(error.errorDescription?.contains("OSStatus -1712") == true)
    }

    @Test("spotifyCommandFailed with empty message still produces a description")
    func spotifyCommandFailedEmptyMessage() {
        let error = AutoHushError.spotifyCommandFailed("")
        #expect(error.errorDescription?.isEmpty == false)
    }
}
