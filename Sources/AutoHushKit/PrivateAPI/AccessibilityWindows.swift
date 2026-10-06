import ApplicationServices
import Darwin

/// The undocumented HIServices function `_AXUIElementCreateWithRemoteToken`:
/// an app's windows on every Space, where the public `kAXWindowsAttribute`
/// lists only those on the current one. Window managers (AltTab among them)
/// have relied on it for years.
///
/// A token names one Accessibility element of a process: its pid, 0, the
/// magic number 0x636f636f ("coco") and the element's number. The windows are
/// found by trying the numbers below `elementLimit` (measured: about 70 ms).
///
/// Resolved at runtime; if a macOS update removes it, `windows(ofProcess:)`
/// returns `nil` and only the current Space's windows can be reached.
///
/// Check after every major macOS release.
package enum AccessibilityWindows {
    /// Element numbers tried. An app's windows have low numbers (measured:
    /// below 100 in Safari web apps).
    static let elementLimit: UInt64 = 1000
    /// How long a single element may take to answer.
    static let timeout: Float = 0.3

    /// Whether the function is there.
    package static var isAvailable: Bool { function != nil }

    /// The process's windows on every Space, minimized ones included; `nil`
    /// when the function is unavailable. Any kind of window counts: a
    /// minimized Safari web app's window calls itself a dialog (measured).
    package static func windows(ofProcess pid: pid_t) -> [AXUIElement]? {
        guard let function else { return nil }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        var windows: [AXUIElement] = []
        for number in 0..<elementLimit {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: number) { Data($0) })
            guard let element = function(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, timeout)
            if string(kAXRoleAttribute, of: element) == kAXWindowRole { windows.append(element) }
        }
        return windows
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private typealias Function = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let function: Function? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
        else { return nil }
        return unsafeBitCast(symbol, to: Function.self)
    }()
}
