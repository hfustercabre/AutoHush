import Foundation
import Testing
@testable import AutoHushKit

@Suite("MusicPlayerError")
struct MusicPlayerErrorTests {

    @Test("automationPermissionDenied has a human-readable description")
    func automationPermissionDeniedDescription() {
        let error = MusicPlayerError.automationPermissionDenied
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.localizedDescription.lowercased().contains("automation"))
    }

    @Test("playerNotRunning, accessibilityPermissionDenied and stillLearning say exactly what bug reports quote", arguments: [
        (MusicPlayerError.playerNotRunning, "The media player isn’t running or isn’t available."),
        (.accessibilityPermissionDenied, "AutoHush isn’t allowed Accessibility access to control the media player."),
        (.stillLearning, "AutoHush is still learning how to control the media player."),
    ])
    func exactDescriptions(error: MusicPlayerError, text: String) {
        #expect(error.errorDescription == text)
    }

    @Test("playerCommandFailed describes its failure, in English for the log")
    func playerCommandFailedDescription() {
        let error = MusicPlayerError.playerCommandFailed(.appleEventError(-1712))
        #expect(error.errorDescription == "Controlling the media player failed: OSStatus -1712.")
        #expect(MusicPlayerError.playerCommandFailed(.menuItemNotFound).errorDescription
                == "Controlling the media player failed: its Play/Pause menu item wasn’t found.")
    }

    @Test("its English, shown in the control-error alert, has no straight apostrophe")
    func curlyApostrophes() {
        let failures: [ControlFailure] = [.menuItemNotFound, .stateUnknown, .nothingToPlay, .buttonDisabled, .pressFailed, .pressIgnored,
                                          .muteUnavailable, .hearingUnavailable, .nowPlayingHidden]
        let errors: [MusicPlayerError] = [.automationPermissionDenied, .accessibilityPermissionDenied, .playerNotRunning,
                                          .playerNotResponding, .stillLearning] + failures.map { .playerCommandFailed($0) }
        #expect(errors.allSatisfy { $0.errorDescription?.contains("'") == false })
    }
}
