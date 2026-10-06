import AppKit
import ApplicationServices

/// The Play/Pause item of an app's playback menu: "Pause" while it plays,
/// "Play" while it's paused, in the app's language. Disabled while there's
/// nothing to play (TIDAL: nobody logged in).
package struct MenuToggle: Equatable, Sendable {
    package let title: String
    package let isEnabled: Bool

    package init(title: String, isEnabled: Bool) {
        self.title = title
        self.isEnabled = isEnabled
    }
}

/// An app's playback menu, read and pressed through Accessibility: for apps
/// that can't be scripted, this is the only way to control that app, not
/// whichever app macOS considers "now playing". Calls block: `MenuPlayer`
/// makes them on a queue of its own. A protocol, so tests can stand in for it.
package protocol PlaybackMenu: Sendable {
    /// Whether AutoHush may use Accessibility; `prompt` shows macOS's request.
    func isTrusted(prompt: Bool) -> Bool
    /// The Play/Pause item of the app running as `pid`; `nil` when the menu
    /// can't be found.
    func toggle(pid: pid_t) -> MenuToggle?
    /// Presses it; `false` when that wasn't possible.
    func pressToggle(pid: pid_t) -> Bool
}

/// The real menu, through the Accessibility API.
///
/// The menu's title is translated, so it's found by its shortcuts instead:
/// it's the menu whose items include ⌘← and ⌘→ (Previous and Next), and its
/// first item is Play or Pause. Measured: TIDAL's Playback menu and Apple
/// Podcasts' Controls menu.
package struct AccessibilityPlaybackMenu: PlaybackMenu {
    /// How long to wait for the app to answer, so a stuck app can't hold
    /// AutoHush up.
    package static let timeout: Float = 0.5

    package init() {}

    package func isTrusted(prompt: Bool) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    package func toggle(pid: pid_t) -> MenuToggle? {
        guard let item = toggleItem(pid: pid) else { return nil }
        return MenuToggle(
            title: Self.value(of: kAXTitleAttribute, in: item) as? String ?? "",
            isEnabled: Self.value(of: kAXEnabledAttribute, in: item) as? Bool ?? false
        )
    }

    package func pressToggle(pid: pid_t) -> Bool {
        guard let item = toggleItem(pid: pid) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Looked up afresh every time: TIDAL rebuilds its whole menu bar
    /// whenever its state changes.
    private func toggleItem(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        guard let menuBar = Self.element(kAXMenuBarAttribute, of: app) else { return nil }
        for menu in Self.children(of: menuBar).compactMap({ Self.children(of: $0).first }) {
            let items = Self.children(of: menu)
            let shortcuts = Set(items.compactMap { item -> Int? in
                // Modifiers 0 is ⌘ alone (kAXMenuItemModifierNone).
                guard Self.value(of: kAXMenuItemCmdModifiersAttribute, in: item) as? Int == 0 else { return nil }
                return Self.value(of: kAXMenuItemCmdVirtualKeyAttribute, in: item) as? Int
            })
            if shortcuts.isSuperset(of: [Self.leftArrow, Self.rightArrow]) { return items.first }
        }
        return nil
    }

    private static let leftArrow = 123
    private static let rightArrow = 124

    private static func value(of attribute: String, in element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = value(of: attribute, in: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (value(of: kAXChildrenAttribute, in: element) as? [AnyObject] ?? []).compactMap { child in
            CFGetTypeID(child) == AXUIElementGetTypeID() ? (child as! AXUIElement) : nil
        }
    }
}
