import Foundation

/// Mission Control's "Move left a Space" and "Move right a Space"
/// (Control-← and Control-→), which the check sends to show another
/// desktop as a person would: turned off in System Settings, they do
/// nothing (tried in the VM, 2026-10-30), and the check can't reach the
/// app on another desktop.
package enum DesktopShortcuts {
    /// Their numbers among macOS's symbolic hot keys.
    static let moveLeft = "79", moveRight = "81"

    /// Whether both are on, as System Settings last saved them.
    package static var areOn: Bool {
        areOn(in: CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any])
    }

    /// Both on in `hotKeys`; one never changed isn't listed, and is on.
    static func areOn(in hotKeys: [String: Any]?) -> Bool {
        [moveLeft, moveRight].allSatisfy { ((hotKeys?[$0] as? [String: Any])?["enabled"] as? Bool) ?? true }
    }
}
