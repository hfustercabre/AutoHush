import Foundation

/// Panes of System Settings the app links to: three privacy panes,
/// Notifications, Menu Bar (where Now Playing is shown or hidden), and
/// Keyboard (its Keyboard Shortcuts, the desktops' among them).
package enum SystemSettingsPane: String {
    case automation = "Privacy_Automation"
    case accessibility = "Privacy_Accessibility"
    case audioCapture = "Privacy_AudioCapture"
    case notifications = "Notifications"
    /// Menu Bar from macOS 26, Control Center before: the same pane
    /// (opened so on macOS 27, 2026-10-16).
    case menuBar = "MenuBar"
    case keyboard = "Keyboard"

    package var url: URL {
        switch self {
        case .automation, .accessibility, .audioCapture:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        case .notifications:
            URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        case .menuBar:
            URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
        case .keyboard:
            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        }
    }
}
