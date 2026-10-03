import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("Permission")
struct PermissionTests {
    @Test("each permission names what to grant and where", arguments: [
        (Permission.automation(player: "Spotify"), "Allow Spotify Automation Access…", SystemSettingsPane.automation),
        (Permission.systemAudioRecording, "Allow Audio Recording Access…", SystemSettingsPane.audioCapture),
    ])
    func grant(permission: Permission, title: String, pane: SystemSettingsPane) {
        #expect(permission.grantTitle == title)
        #expect(permission.settingsPane == pane)
    }

    @Test("System Settings links open the privacy panes")
    func paneLinks() {
        #expect(SystemSettingsPane.automation.url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        #expect(SystemSettingsPane.audioCapture.url.absoluteString.hasSuffix("?Privacy_AudioCapture"))
    }
}
