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
        let bar = MainMenu.make(about: { opened.append("about") }, settings: { opened.append("settings") },
                                find: { opened.append("find") })
        #expect(bar.items.count == 3) // AutoHush, Edit, Window
        let items = bar.items.flatMap { $0.submenu?.items ?? [] }
        let shortcuts = items.filter { !$0.keyEquivalent.isEmpty }
            .map { "\(shortcut($0)) \($0.action.map(NSStringFromSelector) ?? "")" }
        #expect(shortcuts == ["⌘, run", "⌘H hide:", "⌥⌘H hideOtherApplications:", "⌘Q terminate:",
                              "⌘Z undo:", "⇧⌘Z redo:", "⌘X cut:", "⌘C copy:", "⌘V paste:", "⌘A selectAll:", "⌘F run",
                              "⌘W performClose:", "⌘M performMiniaturize:"])

        // About and Settings… open those pages of Settings; Find… the search.
        for title in ["About AutoHush", "Settings…", "Find…"] {
            let item = try #require(items.first { $0.title == title })
            NSApp.sendAction(try #require(item.action), to: item.target, from: item)
        }
        #expect(opened == ["about", "settings", "find"])
        #expect(NSApp.windowsMenu === bar.items[2].submenu)
    }

    @Test("Find… is dimmed while the window in front has no search")
    func findDimmed() throws {
        _ = NSApplication.shared
        final class Search { var shows = false }
        let search = Search()
        let bar = MainMenu.make(about: {}, settings: {}, canFind: { search.shows })
        let find = try #require(bar.items[1].submenu?.items.first { $0.title == "Find…" })
        let target = try #require(find.target as? NSMenuItemValidation)
        #expect(!target.validateMenuItem(find))
        search.shows = true
        #expect(target.validateMenuItem(find))
    }

    @Test("Find… goes to Sound Sources' search while it lists apps, the welcome window's over many players, the logs' or Add an App's list of apps; nowhere else")
    func findTargets() {
        func target(_ window: FindTarget.Window, page: SettingsWindowController.Page? = nil, hasApps: Bool = true,
                    showsPlayers: Bool = true, searchable: Bool = true) -> FindTarget? {
            FindTarget(window: window, settingsPage: page, hasApps: hasApps, welcomeShowsPlayers: showsPlayers,
                       playersSearchable: searchable)
        }
        #expect(target(.settings, page: .soundSources) == .soundSourcesSearch)
        #expect(target(.settings, page: .soundSources, hasApps: false) == nil) // its magnifier is dimmed too
        #expect(target(.settings, page: .general) == nil)
        #expect(target(.welcome) == .welcomeSearch)
        #expect(target(.welcome, searchable: false) == nil)
        #expect(target(.welcome, showsPlayers: false) == nil) // the permissions page
        #expect(target(.logs) == .logsSearch)
        #expect(target(.appChooser) == .appChooserSearch)
        #expect(target(.other) == nil) // Add a Web App's address isn't a search; learning has none
    }

    @Test("Find… puts the keyboard in the window's first field one can type into")
    func findField() {
        // A label first, then the search, deeper down.
        let content = NSView()
        let label = NSTextField(labelWithString: "Apps")
        let row = NSView()
        let search = NSTextField(string: "")
        row.addSubview(search)
        content.addSubview(label)
        content.addSubview(row)
        #expect(content.firstEditableTextField === search)
        #expect(label.firstEditableTextField == nil)
    }
}
