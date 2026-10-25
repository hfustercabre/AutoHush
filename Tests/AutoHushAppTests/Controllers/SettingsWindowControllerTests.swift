import AppKit
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// Each window keeps its place under a name of its own, which AppKit gives
/// one window at a time: tests run at once, each with its own, removed after.
@Suite("SettingsWindowController")
@MainActor
final class SettingsWindowControllerTests {
    private let actions = FakeAppActions()
    private let updates = FakeUpdateCommands()
    private let frameName = "SettingsWindowControllerTests-\(UUID().uuidString)"

    deinit {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
    }

    private func makeController(_ model: SettingsModel? = nil) -> SettingsWindowController {
        SettingsWindowController(model: model ?? .forTests(actions: actions, updates: updates), frameName: frameName)
    }

    private func makeModel() -> SettingsModel { .forTests(actions: actions, updates: updates) }

    @Test("has a sidebar of pages in three groups beside the page, and opens on the one asked for, named in the title; centered the first time")
    func pages() throws {
        let sut = makeController() // never opened before
        let split = try #require(sut.window?.contentViewController as? NSSplitViewController)
        #expect(split.splitViewItems.count == 2)
        #expect(split.splitViewItems.first?.behavior == .sidebar)
        #expect(SettingsWindowController.Page.groups.map { $0.map(\.title) }
                == [["General", "Media Player", "Sound Sources"], ["Behavior"], ["Diagnostics", "About"]])
        #expect(Set(SettingsWindowController.Page.groups.joined()) == Set(SettingsWindowController.Page.allCases))
        #expect(sut.shownPage == nil) // not on screen

        sut.show(page: .diagnostics)
        defer { sut.close() }
        let window = try #require(sut.window)
        let area = try #require(window.screen?.visibleFrame)
        #expect(abs(window.frame.midX - area.midX) <= 1)
        #expect(sut.shownPage == .diagnostics)
        #expect(sut.window?.title == "Diagnostics")
        sut.show(page: .about) // the menu's About button
        #expect(sut.shownPage == .about)
        #expect(sut.window?.title == "About")
    }

    @Test("the window resizes between its limits; the sidebar keeps its width")
    func limits() throws {
        let sut = makeController()
        let window = try #require(sut.window)
        #expect(window.styleMask.contains(.resizable))
        // At least 715 × 560, wider when a choice needs it in the app's language.
        #expect(window.contentMinSize == SettingsWindowController.minimumSize)
        #expect(window.contentMinSize.width >= 715 && window.contentMinSize.height == 600)
        #expect(window.contentMaxSize == SettingsWindowController.maximumSize)
        #expect(window.contentMaxSize.width >= 875 && window.contentMaxSize.height == 900)
        let sidebar = try #require((window.contentViewController as? NSSplitViewController)?.splitViewItems.first)
        #expect(sidebar.minimumThickness == SettingsWindowController.sidebarWidth)
        #expect(sidebar.maximumThickness == SettingsWindowController.sidebarWidth)
        #expect(!sidebar.canCollapse)
        // Kept between launches: the controller gives its window its name
        // (on macOS 14 and 15 it would clear one set before); the app's own
        // is "Settings".
        #expect(sut.windowFrameAutosaveName == frameName)
        #expect(window.frameAutosaveName == frameName)
        #expect(SettingsWindowController.frameName == "Settings")
        #expect(window.collectionBehavior.contains(.fullScreenNone)) // never full screen
    }

    @Test("closed and opened again, Settings is back on General; while open, it keeps its page")
    func reopensOnGeneral() {
        let sut = makeController()
        defer { sut.close() }
        sut.show()
        #expect(sut.shownPage == .general)
        sut.show(page: .behavior)
        sut.show() // Settings in the menu while the window is open
        #expect(sut.shownPage == .behavior)

        sut.close()
        sut.show()
        #expect(sut.shownPage == .general)
    }

    @Test("minimized, Settings is still open: it keeps its page, and shows again as it was")
    func minimizedIsOpen() async throws {
        let model = makeModel()
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .behavior)
        model.foldedDiagnostics = [.apps]
        let window = try #require(sut.window)
        window.miniaturize(nil)
        await TestWait.until { window.isMiniaturized }
        #expect(!window.isVisible && window.isOpen) // macOS counts it as not visible
        #expect(sut.shownPage == .behavior)

        sut.show() // Settings in the menu
        await TestWait.until { !window.isMiniaturized }
        #expect(!window.isMiniaturized && sut.shownPage == .behavior)
        #expect(model.foldedDiagnostics == [.apps]) // not reopened
    }

    @Test("reopened, Sound Sources' search is closed and every part of Diagnostics open")
    func reopensFresh() async {
        let model = makeModel()
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .soundSources)
        model.appList.search = "chr"
        model.foldedDiagnostics = [.apps]
        sut.show(page: .diagnostics)
        #expect(model.appList.search == "chr") // still open while the window is
        #expect(model.foldedDiagnostics == [.apps])

        await TestWait.until { !sut.keys.sidebar.rows.isEmpty } // its rows, as they register
        sut.keys.handle(.left) // the highlight on the sidebar
        #expect(sut.keys.side == .sidebar)

        sut.close()
        sut.show()
        #expect(model.appList.search == nil)
        #expect(model.foldedDiagnostics.isEmpty)
        #expect(sut.keys.side == .page && sut.keys.sidebar.highlighted == nil) // nothing highlighted
    }

    @Test("a size kept from before narrower or lower than its least is brought up to it as it opens")
    func keptSizeTooSmall() throws {
        UserDefaults.standard.set("100 100 600 500 0 0 1440 875 ", forKey: "NSWindow Frame \(frameName)")
        let sut = makeController()
        let content = try #require(sut.window?.contentView?.frame.size)
        #expect(content.width >= SettingsWindowController.minimumSize.width)
        #expect(content.height >= SettingsWindowController.minimumSize.height)
    }

    @Test("its keys go to the highlight only in its own window, without a sheet, and not with ⌘ ⌥ ⌃")
    func keyRouting() async throws {
        let sut = makeController()
        defer { sut.close() }
        sut.show(page: .behavior)
        let window = try #require(sut.window)
        await TestWait.until { !sut.keys.page.rows.isEmpty } // its controls, as they register
        #expect(!sut.handleKey(125, flags: [], windowNumber: window.windowNumber + 1)) // another window's
        #expect(!sut.handleKey(125, flags: .command, windowNumber: window.windowNumber))
        #expect(!sut.handleKey(0, flags: [], windowNumber: window.windowNumber)) // A: not a key of the highlight's
        #expect(sut.handleKey(125, flags: [], windowNumber: window.windowNumber)) // ↓
        #expect(sut.keys.page.highlighted != nil)
        #expect(!sut.handleKey(48, flags: [], windowNumber: window.windowNumber)) // Tab: the window's
        #expect(sut.keys.page.highlighted == nil)
    }
    @Test("on Sound Sources, Delete removes the selected apps, as Remove does; with none selected, or on another page, it isn't taken")
    func deleteRemovesSelected() async throws {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let arc = AudioSource(id: "com.example.arc", name: "Arc")
        preferences.recordSeen([arc])
        let model = SettingsModel.forTests(actions: actions, updates: updates, settings: UserSettings(preferences: preferences))
        model.state.status.seenApps = [arc]
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .behavior)
        let window = try #require(sut.window)
        model.appList.click(on: arc.id, command: false, shift: false)
        #expect(!sut.handleKey(51, flags: [], windowNumber: window.windowNumber)) // another page
        sut.show(page: .soundSources)
        #expect(sut.handleKey(51, flags: [], windowNumber: window.windowNumber))
        #expect(model.appList.selectedApps.isEmpty && preferences.seenApps.isEmpty)
        #expect(!sut.handleKey(51, flags: [], windowNumber: window.windowNumber)) // none selected
    }
}
