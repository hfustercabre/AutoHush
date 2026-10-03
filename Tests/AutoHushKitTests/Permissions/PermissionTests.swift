import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("Permission")
struct PermissionTests {
    @Test("each permission is granted in its own System Settings pane", arguments: [
        (Permission.automation(player: "Spotify"), SystemSettingsPane.automation),
        (Permission.systemAudioRecording, SystemSettingsPane.audioCapture),
    ])
    func pane(permission: Permission, pane: SystemSettingsPane) {
        #expect(permission.settingsPane == pane)
    }

    @Test("System Settings links open the privacy panes")
    func paneLinks() {
        #expect(SystemSettingsPane.automation.url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        #expect(SystemSettingsPane.audioCapture.url.absoluteString.hasSuffix("?Privacy_AudioCapture"))
    }
}
