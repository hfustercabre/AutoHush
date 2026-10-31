import CoreGraphics
import Foundation

/// Mission Control's "Move left a Space" and "Move right a Space"
/// (Control-← and Control-→ unless the user set other keys), which the
/// check presses to show another desktop as a person would: turned off in
/// System Settings, they do nothing (tried in the VM, 2026-10-30), and the
/// check can't reach the app on another desktop.
package enum DesktopShortcuts {
    /// Their numbers among macOS's symbolic hot keys.
    static let moveLeft = "79", moveRight = "81"

    /// Whether both are on, as System Settings last saved them.
    package static var areOn: Bool { areOn(in: hotKeys) }

    /// The keys one of them is set to, as a key code and the modifiers
    /// pressed with it.
    package struct Keys: Equatable, Sendable {
        package let keyCode: CGKeyCode
        package let flags: CGEventFlags
    }

    /// The keys "Move right a Space" (or left) is set to: the check presses
    /// those, so one the user set to other keys works too (K2, the user,
    /// 2026-10-30).
    package static func keys(right: Bool) -> Keys { keys(right: right, in: hotKeys) }

    /// Read afresh: System Settings may have changed them since the last read.
    private static var hotKeys: [String: Any]? {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        return CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any]
    }

    /// Both on in `hotKeys`; one never changed isn't listed, and is on.
    static func areOn(in hotKeys: [String: Any]?) -> Bool {
        [moveLeft, moveRight].allSatisfy { ((hotKeys?[$0] as? [String: Any])?["enabled"] as? Bool) ?? true }
    }

    /// One's keys in `hotKeys`: its value's parameters are a character, a
    /// key code and the modifiers (CGEventFlags' bits). One never changed,
    /// or with no key, is Control and the arrow, with Fn, as macOS stores it.
    static func keys(right: Bool, in hotKeys: [String: Any]?) -> Keys {
        let standard = Keys(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
        let value = (hotKeys?[right ? moveRight : moveLeft] as? [String: Any])?["value"] as? [String: Any]
        guard let parameters = value?["parameters"] as? [Int], parameters.count == 3,
              let keyCode = CGKeyCode(exactly: parameters[1]), keyCode != CGKeyCode.max,
              let flags = UInt64(exactly: parameters[2]) else { return standard }
        return Keys(keyCode: keyCode, flags: CGEventFlags(rawValue: flags))
    }
}
