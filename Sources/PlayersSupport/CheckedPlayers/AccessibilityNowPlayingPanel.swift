import AppKit
import ApplicationServices
import AutoHushKit

/// The real panel (macOS 26 on): its menu bar item found in the menu bar's
/// own windows (else by hit-testing along it), its rows read from Control
/// Center's windows. Player Check opens, reads and closes it with the same
/// calls.
package struct AccessibilityNowPlayingPanel: NowPlayingPanel {
    /// A row as the open panel shows it, with its Play/Pause.
    package typealias ShownRow = (row: PanelRow, button: AXUIElement)

    /// How long a hit-tested point waits for an answer: macOS waits 6 s for
    /// an app that doesn't answer otherwise.
    static let timeout: Float = 0.25
    /// How long MenuBarAgent and Control Center, which draw the menu bar's
    /// items and the panel, get to answer each read.
    static let ownTimeout: Float = 1

    package init() {}

    package func isInMenuBar() -> Bool { Self.menuItem() != nil }

    package func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        // Hidden by the user: shown for this press only (the user, 2026-10-16),
        // looked for meanwhile only in the menu bar's own windows.
        if Self.menuItem() == nil, NowPlayingSetting.isHidden {
            return NowPlayingSetting.whileShown(until: { Self.listedItem() != nil }) { Self.press(pick) } ?? nil
        }
        return Self.press(pick)
    }

    private static func press(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        guard let item = Self.menuItem(), let rows = Self.open(item) else { return nil }
        defer { Self.close(item) }
        guard let chosen = pick(rows.map(\.row)), let button = rows.first(where: { $0.row == chosen })?.button else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// The menu bar's Now Playing item: in the windows of the app that draws
    /// the menu bar's items, else hit-tested along it. Hidden in System
    /// Settings, it's in neither: macOS removes it.
    package static func menuItem() -> AXUIElement? {
        listedItem() ?? hitTestedItem()
    }

    static let identifier = "com.apple.menuextra.now-playing"

    /// The item in its own window: MenuBarAgent (macOS 27, measured
    /// 2026-10-15; Control Center's before) keeps each menu bar item in a
    /// window, named by its identifier there (its list of the menu bar's
    /// items doesn't name them), wherever it is and whatever covers it: a
    /// wide app's menus by the notch, another app's window over it.
    package static func listedItem() -> AXUIElement? {
        for id in ["com.apple.MenuBarAgent", "com.apple.controlcenter"] {
            guard let app = NSRunningApplication.running(id) else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, ownTimeout)
            func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
                // Each element waits macOS's default otherwise, not its app's.
                AXUIElementSetMessagingTimeout(element, ownTimeout)
                if element.string(kAXIdentifierAttribute) == identifier { return element }
                guard depth < 4 else { return nil }
                for child in element.children {
                    if let found = find(child, depth: depth + 1) { return found }
                }
                return nil
            }
            for window in element.elements(kAXWindowsAttribute) {
                if let found = find(window, depth: 0) { return found }
            }
        }
        return nil
    }

    /// The item hit-tested along the primary display's menu bar (hit-test
    /// coordinates start at its top left; the main display, read off the
    /// main thread through CoreGraphics, which AppKit's screens aren't): the
    /// topmost thing there, so not while something covers it. A point over
    /// the front app's menus asks that app, so each waits `timeout` at most:
    /// set on the system-wide element, that's this process's own timeout for
    /// every element without one, so it's put back to macOS's default after.
    package static func hitTestedItem() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        defer { AXUIElementSetMessagingTimeout(system, 0) }
        let width = Float(CGDisplayBounds(CGMainDisplayID()).width)
        var x = width - 20
        while x > width / 3 {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, x, 12, &hit) == .success, let hit {
                AXUIElementSetMessagingTimeout(hit, timeout)
                if hit.string(kAXIdentifierAttribute) == identifier { return hit }
            }
            x -= 6
        }
        return nil
    }

    /// Opens the panel with its menu bar item and waits up to 2 s for its
    /// rows; `nil` when the item didn't open. It shows under the menu bar,
    /// and takes the keyboard while it's open.
    package static func open(_ item: AXUIElement) -> [ShownRow]? {
        guard AXUIElementPerformAction(item, kAXPressAction as CFString) == .success else { return nil }
        var rows: [ShownRow] = []
        let deadline = Date().addingTimeInterval(2)
        while rows.isEmpty, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            rows = Self.rows()
        }
        return rows
    }

    /// The open panel's rows, with their Play/Pause; none while it's closed.
    package static func rows() -> [ShownRow] {
        guard let center = NSRunningApplication.running("com.apple.controlcenter") else { return [] }
        var found: [ShownRow] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 20 else { return }
            AXUIElementSetMessagingTimeout(element, ownTimeout)
            let children = element.children
            if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.string(kAXIdentifierAttribute)) }) {
                let text = children.compactMap { $0.string(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
                found.append((PanelRow(text: text, playing: button.string(kAXIdentifierAttribute) == "pause.fill"), button))
                return
            }
            children.forEach { walk($0, depth + 1) }
        }
        let app = AXUIElementCreateApplication(center.processIdentifier)
        AXUIElementSetMessagingTimeout(app, ownTimeout)
        app.elements(kAXWindowsAttribute).forEach { walk($0, 0) }
        return found
    }

    /// Closes it, waiting up to 2 s for its rows to go.
    package static func close(_ item: AXUIElement) {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(2)
        while !rows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
}
