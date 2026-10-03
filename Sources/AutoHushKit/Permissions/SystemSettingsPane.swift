import AppKit

/// Privacy panes of System Settings the app links to.
package enum SystemSettingsPane: String {
    case automation = "Privacy_Automation"
    case audioCapture = "Privacy_AudioCapture"

    package var url: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
    }

    @MainActor
    package func open() {
        NSWorkspace.shared.open(url)
    }
}
