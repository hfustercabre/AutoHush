import AppKit
import ApplicationServices
import AutoHushKit

/// The real panel: its menu bar item found in the windows of the app that
/// draws the menu bar's items (MenuBarAgent or Control Center, both tried on
/// every macOS), else by hit-testing along the menu bar; its rows read from
/// Control Center's windows (macOS 14's laid out as `flatRows` reads them).
/// Player Check opens, reads and closes it with the same calls.
package struct AccessibilityNowPlayingPanel: NowPlayingPanel {
    /// A row as the open panel shows it, with its Play/Pause.
    package typealias ShownRow = (row: PanelRow, button: AXUIElement)

    /// How long a hit-tested point waits for an answer: macOS waits 6 s
    /// otherwise.
    static let timeout: Float = 0.25
    /// How long MenuBarAgent and Control Center, which draw the menu bar's
    /// items and the panel, get to answer each read.
    static let ownTimeout: Float = 1

    package init() {}

    func isInMenuBar() -> Bool { Self.menuItem() != nil }

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
    /// The apps that may draw the menu bar's items, tried in this order on
    /// every macOS: MenuBarAgent (macOS 27's, measured 2026-10-15), then
    /// Control Center.
    static let itemApps = ["com.apple.MenuBarAgent", "com.apple.controlcenter"]

    /// The item in its own window: the app that draws the menu bar's items
    /// keeps each in a window (MenuBarAgent does), named by its identifier
    /// there (its list of the menu bar's items doesn't name them), wherever
    /// it is and whatever covers it: a wide app's menus by the notch,
    /// another app's window over it.
    package static func listedItem() -> AXUIElement? {
        for id in itemApps {
            guard let app = NSRunningApplication.running(id) else { continue }
            // Each element waits macOS's default otherwise, not its app's.
            let element = AXUIElement.application(app.processIdentifier, timeout: ownTimeout)
            func find(_ element: AXUIElement, depth: Int) -> AXUIElement? {
                if element.string(kAXIdentifierAttribute) == identifier { return element }
                guard depth < 4 else { return nil }
                for child in element.children(timeout: ownTimeout) {
                    if let found = find(child, depth: depth + 1) { return found }
                }
                return nil
            }
            for window in element.elements(kAXWindowsAttribute, timeout: ownTimeout) {
                if let found = find(window, depth: 0) { return found }
            }
            // Control Center on macOS 14 keeps its items in its extras menu
            // bar, not in windows (measured on 14.4, 2026-10-18).
            if let extras = element.element("AXExtrasMenuBar", timeout: ownTimeout),
               let found = extras.children(timeout: ownTimeout).first(where: { $0.string(kAXIdentifierAttribute) == identifier }) {
                return found
            }
        }
        return nil
    }

    /// The item hit-tested along the primary display's menu bar (hit-test
    /// coordinates start at its top left; the main display, read off the
    /// main thread through CoreGraphics, which AppKit's screens aren't), in
    /// the apps that may draw it (`itemApps`) only, never in the front app
    /// (its menus) or another app (its item), which may not answer. Each
    /// point waits `timeout` at most, set on each app's element: set on the
    /// system-wide element, it would be every element's in this process
    /// while the sweep runs.
    package static func hitTestedItem() -> AXUIElement? {
        let apps = itemApps.compactMap { NSRunningApplication.running($0) }.map { AXUIElement.application($0.processIdentifier, timeout: timeout) }
        guard !apps.isEmpty else { return nil }
        let width = Float(CGDisplayBounds(CGMainDisplayID()).width)
        var x = width - 20
        while x > width / 3 {
            for app in apps {
                var hit: AXUIElement?
                if AXUIElementCopyElementAtPosition(app, x, 12, &hit) == .success, let hit,
                   hit.waiting(timeout).string(kAXIdentifierAttribute) == identifier {
                    return hit
                }
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
        return Polling.wait(seconds: 2, every: 0.05, lookingFirst: false, reading: Self.rows, until: { !$0.isEmpty })
    }

    /// The open panel's rows, with their Play/Pause; none while it's closed.
    package static func rows() -> [ShownRow] {
        guard let center = NSRunningApplication.running("com.apple.controlcenter") else { return [] }
        var found: [ShownRow] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 20 else { return }
            let children = element.children(timeout: ownTimeout)
            if let button = children.first(where: { ["play.fill", "pause.fill"].contains($0.string(kAXIdentifierAttribute)) }) {
                let text = children.compactMap { $0.string(kAXValueAttribute) }.filter { !$0.isEmpty }.joined(separator: " ")
                found.append((PanelRow(text: text, playing: button.string(kAXIdentifierAttribute) == "pause.fill"), button))
                return
            }
            let flat = flatRows(in: children)
            guard flat.isEmpty else {
                found += flat
                return
            }
            children.forEach { walk($0, depth + 1) }
        }
        AXUIElement.application(center.processIdentifier, timeout: ownTimeout)
            .elements(kAXWindowsAttribute, timeout: ownTimeout).forEach { walk($0, 0) }
        return found
    }

    /// macOS 14's panel: one group with every row's parts in a line (its
    /// text, its Play/Pause, its Next), the buttons named only by their
    /// description, in Control Center's language (measured on 14.4).
    static func flatRows(in children: [AXUIElement]) -> [ShownRow] {
        flatRows(in: children, words: centerWords) { $0.string($1) }
    }

    /// The same over any elements, each attribute read by `read`, `words`
    /// being the Play and Pause it's said in: tests stand in for both.
    static func flatRows<Element>(in children: [Element], words: (play: Set<String>, pause: Set<String>),
                                  read: (Element, String) -> String?) -> [(row: PanelRow, button: Element)] {
        var rows: [(row: PanelRow, button: Element)] = []
        var text: String?
        for child in children {
            switch read(child, kAXRoleAttribute) {
            case kAXStaticTextRole:
                text = read(child, kAXValueAttribute)
            case kAXButtonRole:
                guard let said = text, !said.isEmpty, let word = read(child, kAXDescriptionAttribute)?.lowercased() else { continue }
                // It says what a press does: Pause while the row plays.
                if words.pause.contains(word) { rows.append((PanelRow(text: said, playing: true), child)) }
                else if words.play.contains(word) { rows.append((PanelRow(text: said, playing: false), child)) }
                else { continue }
                text = nil
            default:
                break
            }
        }
        return rows
    }

    /// Control Center's words for its Play and Pause, in every language it
    /// has (its NowPlaying table); English when the table can't be read.
    static let centerWords: (play: Set<String>, pause: Set<String>) = {
        var words: (play: Set<String>, pause: Set<String>) = (["play"], ["pause"])
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/NowPlaying.loctable")
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]]
        else { return words }
        for strings in table.values {
            if let play = strings["play"] as? String { words.play.insert(play.lowercased()) }
            if let pause = strings["pause"] as? String { words.pause.insert(pause.lowercased()) }
        }
        return words
    }()

    /// Closes it, waiting up to 2 s for its rows to go.
    package static func close(_ item: AXUIElement) {
        _ = AXUIElementPerformAction(item, kAXPressAction as CFString)
        Polling.wait(seconds: 2, every: 0.05, until: { rows().isEmpty })
    }
}
