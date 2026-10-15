import AppKit
import ApplicationServices
import AutoHushKit

/// The real panel (macOS 26 on): its menu bar item found by hit-testing
/// along the menu bar, its rows read from Control Center's windows. Player
/// Check opens, reads and closes it with the same calls.
package struct AccessibilityNowPlayingPanel: NowPlayingPanel {
    /// A row as the open panel shows it, with its Play/Pause.
    package typealias ShownRow = (row: PanelRow, button: AXUIElement)

    package init() {}

    package func pressRow(_ pick: ([PanelRow]) -> PanelRow?) -> Bool? {
        guard let item = Self.menuItem(), let rows = Self.open(item) else { return nil }
        defer { Self.close(item) }
        guard let chosen = pick(rows.map(\.row)), let button = rows.first(where: { $0.row == chosen })?.button else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// The menu bar's Now Playing item: the menu bar's own list doesn't name
    /// it, so it's hit-tested along the primary display's menu bar (hit-test
    /// coordinates start at its top left; `NSScreen.main` may be another).
    package static func menuItem() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        let width = Float(NSScreen.screens.first?.frame.width ?? 1470)
        var x = width - 20
        while x > width / 3 {
            var hit: AXUIElement?
            if AXUIElementCopyElementAtPosition(system, x, 12, &hit) == .success, let hit,
               hit.string(kAXIdentifierAttribute) == "com.apple.menuextra.now-playing" { return hit }
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
            let children = element.children
            if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.string(kAXIdentifierAttribute)) }) {
                let text = children.compactMap { $0.string(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
                found.append((PanelRow(text: text, playing: button.string(kAXIdentifierAttribute) == "pause.fill"), button))
                return
            }
            children.forEach { walk($0, depth + 1) }
        }
        AXUIElementCreateApplication(center.processIdentifier).elements(kAXWindowsAttribute).forEach { walk($0, 0) }
        return found
    }

    /// Closes it, waiting up to 2 s for its rows to go.
    package static func close(_ item: AXUIElement) {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        let deadline = Date().addingTimeInterval(2)
        while !rows().isEmpty, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }
}
