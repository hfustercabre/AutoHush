import AppKit
import Testing
@testable import AutoHushApp

@Suite("MainMenu")
@MainActor
struct MainMenuTests {
    /// "⇧⌘Z" for an item's keyboard shortcut.
    private func shortcut(_ item: NSMenuItem) -> String {
        let mask = item.keyEquivalentModifierMask
        return (mask.contains(.option) ? "⌥" : "") + (mask.contains(.shift) ? "⇧" : "") + (mask.contains(.command) ? "⌘" : "")
            + item.keyEquivalent.uppercased()
    }

    @Test("the menu bar has the Mac's standard menus with Apple's shortcuts, and none of AutoHush's own")
    func standardShortcuts() throws {
        _ = NSApplication.shared
        var opened: [String] = []
        let bar = MainMenu.make(about: { opened.append("about") }, settings: { opened.append("settings") })
        #expect(bar.items.count == 3) // AutoHush, Edit, Window
        let items = bar.items.flatMap { $0.submenu?.items ?? [] }
        let shortcuts = items.filter { !$0.keyEquivalent.isEmpty }
            .map { "\(shortcut($0)) \($0.action.map(NSStringFromSelector) ?? "")" }
        #expect(shortcuts == ["⌘, run", "⌘H hide:", "⌥⌘H hideOtherApplications:", "⌘Q terminate:",
                              "⌘Z undo:", "⇧⌘Z redo:", "⌘X cut:", "⌘C copy:", "⌘V paste:", "⌘A selectAll:",
                              "⌘W performClose:", "⌘M performMiniaturize:"])

        // About and Settings… open those pages of Settings.
        for title in ["About AutoHush", "Settings…"] {
            let item = try #require(items.first { $0.title == title })
            NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        }
        #expect(opened == ["about", "settings"])
        #expect(NSApp.windowsMenu === bar.items[2].submenu)
    }
}
