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

    @Test("playerCommandFailed describes its failure, in English for the log")
    func playerCommandFailedDescription() {
        let error = MusicPlayerError.playerCommandFailed(.appleEventError(-1712, message: nil))
        #expect(error.errorDescription == "Controlling the music player failed: OSStatus -1712.")
        #expect(MusicPlayerError.playerCommandFailed(.appleEventError(-1708, message: "Not understood")).errorDescription
                == "Controlling the music player failed: Not understood (OSStatus -1708).")
        #expect(MusicPlayerError.playerCommandFailed(.menuItemNotFound).errorDescription
                == "Controlling the music player failed: its Play/Pause menu item wasn't found.")
    }
}
