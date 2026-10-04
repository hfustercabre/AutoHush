import Foundation

/// Panes of System Settings the app links to: two privacy panes, and
/// Notifications.
package enum SystemSettingsPane: String {
    case automation = "Privacy_Automation"
    case audioCapture = "Privacy_AudioCapture"
    case notifications = "Notifications"

    package var url: URL {
        switch self {
        case .automation, .audioCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
    }
}
