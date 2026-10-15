import AppKit
import ApplicationServices
import AutoHushKit

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
/// Podcasts' Controls menu. Else, as Player Check finds it, one whose first
/// item is on Space and whose items include ← and → under other modifiers
/// (Deezer's Play menu: Space, ⇧← and ⇧→).
package struct AccessibilityPlaybackMenu: PlaybackMenu {
    /// How long to wait for the app to answer, so a stuck app can't hold
    /// AutoHush up.
    package static let timeout: Float = 0.5

    package init() {}

    package func isTrusted(prompt: Bool) -> Bool {
        AccessibilityPermission.isTrusted(prompt: prompt)
    }

    package func toggle(pid: pid_t) -> MenuToggle? {
        guard let item = toggleItem(pid: pid) else { return nil }
        return MenuToggle(
            title: item.string(kAXTitleAttribute) ?? "",
            isEnabled: item.value(kAXEnabledAttribute) as? Bool ?? false
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
        guard let menuBar = app.element(kAXMenuBarAttribute) else { return nil }
        var onOtherArrows: AXUIElement?
        for menu in menuBar.children.compactMap({ $0.children.first }) {
            let items = menu.children
            var withCommand: Set<Int> = [], anyModifiers: Set<Int> = []
            for item in items {
                guard let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int else { continue }
                anyModifiers.insert(key)
                // Modifiers 0 is ⌘ alone (kAXMenuItemModifierNone).
                if item.value(kAXMenuItemCmdModifiersAttribute) as? Int == 0 { withCommand.insert(key) }
            }
            if withCommand.isSuperset(of: Self.arrows) { return items.first }
            if onOtherArrows == nil, anyModifiers.isSuperset(of: Self.arrows),
               items.first?.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int == Self.space {
                onOtherArrows = items.first
            }
        }
        return onOtherArrows
    }

    /// ← and → (Previous and Next).
    private static let arrows: Set<Int> = [123, 124]
    private static let space = 49
}
