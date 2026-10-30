import AppKit
import ApplicationServices
import AutoHushKit

/// The real menu, through the Accessibility API.
///
/// The menu's title is translated, so it's found by its shortcuts instead:
/// it's the menu whose items include ⌘← and ⌘→ (Previous and Next), and its
/// first item is Play or Pause. Measured: TIDAL's Playback menu and Apple
/// Podcasts' Controls menu. Else, as Player Check finds it, one whose first
/// item is on Space and whose items include ← and → under other modifiers
/// (Deezer's Play menu: Space, ⇧← and ⇧→).
package struct AccessibilityPlaybackMenu: PlaybackMenu {
    /// How long to wait for the app to answer each read (its menu bar, each
    /// menu and item), so a stuck app can't hold AutoHush up.
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
        guard let menuBar = Self.menuBar(of: pid) else { return nil }
        return Self.playbackMenu(in: menuBar)?.toggle
    }

    /// The menu bar of the app running as `pid`, read waiting `timeout`.
    package static func menuBar(of pid: pid_t) -> AXUIElement? {
        AXUIElement.application(pid, timeout: timeout).element(kAXMenuBarAttribute, timeout: timeout)
    }

    /// The playback menu in an app's `menuBar`, as AutoHush finds it: the
    /// one whose items include ⌘← and ⌘→ (each saying its modifiers are ⌘
    /// alone), else one whose first item is on Space and whose items include
    /// ← and → under any modifiers; its menu bar item, and its first item.
    /// Player Check finds an app's menu with this, so a check keeps only a
    /// menu AutoHush finds. Each element read waits `timeout`.
    package static func playbackMenu(in menuBar: AXUIElement) -> (barItem: AXUIElement, toggle: AXUIElement)? {
        var onOtherArrows: (barItem: AXUIElement, toggle: AXUIElement)?
        for barItem in menuBar.children(timeout: timeout) {
            guard let menu = barItem.children(timeout: timeout).first else { continue }
            let items = menu.children(timeout: timeout)
            guard let first = items.first else { continue }
            var withCommand: Set<Int> = [], anyModifiers: Set<Int> = []
            for item in items {
                guard let key = item.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int else { continue }
                anyModifiers.insert(key)
                // Modifiers 0 is ⌘ alone (kAXMenuItemModifierNone).
                if item.value(kAXMenuItemCmdModifiersAttribute) as? Int == 0 { withCommand.insert(key) }
            }
            if withCommand.isSuperset(of: arrows) { return (barItem, first) }
            if onOtherArrows == nil, anyModifiers.isSuperset(of: arrows),
               first.value(kAXMenuItemCmdVirtualKeyAttribute) as? Int == space {
                onOtherArrows = (barItem, first)
            }
        }
        return onOtherArrows
    }

    /// ← and → (Previous and Next), and Space, by their key codes.
    package static let arrows: Set<Int> = [123, 124]
    static let space = 49
}
