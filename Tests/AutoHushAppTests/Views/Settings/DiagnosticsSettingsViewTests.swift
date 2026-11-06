import Testing
@testable import AutoHushApp
import AutoHushKit

/// Settings → Diagnostics' fix buttons, as VoiceOver hears them.
@Suite("DiagnosticsSettingsView")
@MainActor
struct DiagnosticsSettingsViewTests {
    @Test("a short Allow… or Choose… says what it allows or chooses, starting with the word it shows (VO9)")
    func spokenFixTitles() {
        typealias Fix = DiagnosticsSnapshot.Row.Fix
        #expect(DiagnosticsSettingsView.title(of: .allow(.systemAudioRecording)) == "Allow…")
        #expect(DiagnosticsSettingsView.spokenTitle(of: .allow(.systemAudioRecording)) == "Allow Audio Recording Access…")
        #expect(DiagnosticsSettingsView.spokenTitle(of: .allow(.accessibility(player: "Jukebox"))) == "Allow Accessibility Access…")
        #expect(DiagnosticsSettingsView.spokenTitle(of: .allow(.automation(player: "Jukebox"))) == "Allow Jukebox Automation Access…")
        #expect(DiagnosticsSettingsView.spokenTitle(of: .choosePlayer) == "Choose Player")
        #expect(DiagnosticsSettingsView.spokenTitle(of: .learnControls) == DiagnosticsSettingsView.title(of: .learnControls))
        // Two Allow… at once are told apart.
        let fixes: [Fix] = [.allow(.systemAudioRecording), .allow(.accessibility(player: "Jukebox"))]
        #expect(Set(fixes.map(DiagnosticsSettingsView.spokenTitle(of:))).count == 2)
    }
}
