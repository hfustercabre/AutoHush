import ApplicationServices

/// The Accessibility permission, which pressing another app's menus and
/// buttons needs (TIDAL, Apple Podcasts, Safari web apps, Safari's Add to
/// Dock).
package enum AccessibilityPermission {
    /// Whether AutoHush may use Accessibility; `prompt` shows macOS's
    /// request (once per launch, macOS decides), which also lists AutoHush
    /// in System Settings.
    package static func isTrusted(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
}
