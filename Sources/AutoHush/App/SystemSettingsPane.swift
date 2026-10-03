import AppKit

/// Privacy panes of System Settings the app links to.
enum SystemSettingsPane: String {
    case automation = "Privacy_Automation"
    case audioCapture = "Privacy_AudioCapture"

    var url: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
    }

    @MainActor
    func open() {
        NSWorkspace.shared.open(url)
    }
}
