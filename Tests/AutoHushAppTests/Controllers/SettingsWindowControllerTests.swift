import AppKit
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// Each window keeps its place under a name of its own, which AppKit gives
/// one window at a time: tests run at once, each with its own, removed after.
@Suite("SettingsWindowController", .waitsTimeLimit, .application)
@MainActor
final class SettingsWindowControllerTests {
    private let actions = FakeAppActions()
    private let updates = FakeUpdateCommands()
    private let frameName = "SettingsWindowControllerTests-\(UUID().uuidString)"

    deinit {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
    }

    /// Its highlights moved by the keys alone: the pointer, resting wherever
    /// the window opens, moves neither (T-5).
    private func makeController(_ model: SettingsModel? = nil) -> SettingsWindowController {
        let sut = SettingsWindowController(model: model ?? .forTests(actions: actions, updates: updates), frameName: frameName)
        sut.keys.sidebar.followsPointer = false
        sut.keys.page.followsPointer = false
        sut.fullKeyboardAccess = { false }
        return sut
    }

    private func makeModel() -> SettingsModel { .forTests(actions: actions, updates: updates) }

    @Test("has a sidebar of pages in three groups beside the page, and opens on the one asked for, named in the title; centered the first time")
    func pages() throws {
        let sut = makeController() // never opened before
        let split = try #require(sut.window?.contentViewController as? NSSplitViewController)
        #expect(split.splitViewItems.count == 2)
        #expect(split.splitViewItems.first?.behavior == .sidebar)
        #expect(SettingsPage.groups.map { $0.pages.map(\.title) }
                == [["General", "Media Player", "Sound Sources", "Behavior"], ["Fine-Tuning", "Diagnostics"], ["About"]])
        #expect(SettingsPage.groups.map(\.title) == ["Everyday", "Advanced", nil])
        #expect(Set(SettingsPage.groups.flatMap(\.pages)) == Set(SettingsPage.allCases))
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
        // At least 715 × 650, wider when a choice needs it in the app's language.
        #expect(window.contentMinSize == SettingsWindowController.minimumSize)
        #expect(window.contentMinSize.width >= 715 && window.contentMinSize.height == 650)
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

    @Test("the Fine-Tuning card a Behavior row asked for is forgotten once another page shows")
    func fineTuningFocusForgotten() {
        let model = makeModel()
        let sut = makeController(model)
        defer { sut.close() }
        model.fineTuningFocus = .detection
        sut.show(page: .fineTuning)
        #expect(model.fineTuningFocus == .detection)
        sut.show(page: .behavior)
        #expect(model.fineTuningFocus == nil)
    }

    @Test("a page shown by a key's press, or VoiceOver's, lights its first control, where VoiceOver's cursor goes; once, and not for a page shown otherwise (N8)")
    func shownPageTakesHighlight() async throws {
        let model = makeModel()
        model.state.status.choosePlayer(named: "Jukebox")
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .general)
        await TestWait.until { !sut.keys.page.rows.isEmpty }
        #expect(sut.keys.page.highlighted == nil)
        model.shownPageTakesHighlight = true // General's Change…, pressed so (`SettingsModel.showPage`)
        sut.show(page: .mediaPlayer)
        await TestWait.until { sut.keys.page.highlighted != nil }
        // The page's first, past the toolbar's Back, which only Tab stops on (R2).
        let first = try #require(sut.keys.page.rows.joined().first { sut.keys.page.controls[$0]?.tabOnly != true })
        #expect(sut.keys.page.highlighted == first)
        #expect(sut.keys.page.light(first).arrivals == 1 && sut.keys.page.light(first).byKeys)
        #expect(!model.shownPageTakesHighlight)

        // Shown from the sidebar or by a click: nothing lit.
        sut.show(page: .behavior)
        await TestWait.until { sut.keys.page.highlighted == nil && !sut.keys.page.rows.isEmpty }
        for _ in 0..<5 { await Task.yield() }
        #expect(sut.keys.page.highlighted == nil)
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

    @Test("Back and Forward walk the pages shown, as System Settings': a Behavior row's Fine-Tuning goes back to Behavior; opened afresh, nothing to go back to")
    func backAndForward() throws {
        let sut = makeController()
        defer { sut.close() }
        sut.show()
        #expect(!sut.canGoBack && !sut.canGoForward)
        sut.show(page: .behavior)
        sut.show(page: .fineTuning) // a Behavior row
        #expect(sut.canGoBack && !sut.canGoForward)

        sut.goBack(nil)
        #expect(sut.shownPage == .behavior && sut.window?.title == "Behavior")
        #expect(sut.canGoBack && sut.canGoForward)
        sut.goForward(nil)
        #expect(sut.shownPage == .fineTuning && !sut.canGoForward)

        // The View menu's items follow: dimmed with nothing to go to.
        let back = NSMenuItem(title: "Back", action: #selector(SettingsWindowController.goBack(_:)), keyEquivalent: "[")
        let forward = NSMenuItem(title: "Forward", action: #selector(SettingsWindowController.goForward(_:)), keyEquivalent: "]")
        #expect(sut.validateMenuItem(back) && !sut.validateMenuItem(forward))

        // The toolbar has them, joined, before the page's name: its ‹ goes back,
        // dimmed with nothing to go to.
        let toolbar = try #require(sut.window?.toolbar)
        let arrows = try #require(toolbar.items.first { $0.itemIdentifier.rawValue == "history" } as? NSToolbarItemGroup)
        #expect(arrows.subitems.map(\.isEnabled) == [true, false])
        arrows.selectedIndex = 0
        NSApp.sendAction(try #require(arrows.action), to: arrows.target, from: arrows)
        #expect(sut.shownPage == .behavior && arrows.subitems.map(\.isEnabled) == [true, true])
        sut.goForward(nil)

        sut.close()
        sut.show()
        #expect(sut.shownPage == .general && !sut.canGoBack && !sut.canGoForward)
    }

    @Test("Tab and Shift-Tab reach the toolbar's Back and Forward, first in the page's order, a ring over the lit one; Return presses it; dimmed with nowhere to go, they're skipped; ↓ goes past them, as before (R2)")
    func toolbarArrowsByTab() async throws {
        let sut = makeController()
        defer { sut.close() }
        sut.show()
        sut.show(page: .behavior)
        sut.show(page: .fineTuning)
        sut.goBack(nil) // on Behavior: Back and Forward both go somewhere
        let window = try #require(sut.window)
        let page = sut.keys.page
        let arrows = sut.toolbarKeys
        await TestWait.until {
            SettingsToolbarKeys.findArrows(in: window) != nil
                && page.controls.contains { !$0.value.tabOnly && $0.value.frame != .zero }
        }
        let key = { (keyCode: UInt16, flags: NSEvent.ModifierFlags) in sut.handleKey(keyCode, flags: flags, windowNumber: window.windowNumber) }
        #expect(key(125, [])) // ↓ from nothing: the page's first control, past the arrows
        let first = try #require(page.highlighted)
        #expect(first != arrows.back && first != arrows.forward)
        page.clear()
        #expect(key(48, [])) // Tab from nothing: Back
        #expect(page.highlighted == arrows.back)
        // Its ring, over the toolbar's left arrow, in a window of its own above Settings.
        let ring = try #require(arrows.ringWindow)
        let group = try #require(SettingsToolbarKeys.findArrows(in: window))
        let backOnScreen = window.convertToScreen(group.divided(atDistance: group.width / 2, from: .minXEdge).slice)
        #expect(ring.parent === window && ring.isVisible && ring.ignoresMouseEvents)
        #expect(abs(ring.frame.midX - backOnScreen.midX) <= 1 && abs(ring.frame.midY - backOnScreen.midY) <= 1)
        #expect(key(48, [])) // Tab: Forward
        #expect(page.highlighted == arrows.forward)
        #expect(key(48, [])) // Tab: the page's first control; no ring left
        #expect(page.highlighted == first && arrows.ringWindow == nil)
        #expect(key(48, .shift)) // Shift-Tab: Forward
        #expect(page.highlighted == arrows.forward)
        #expect(key(36, [])) // Return: Forward, to Fine-Tuning, where it dims
        #expect(sut.shownPage == .fineTuning && !sut.canGoForward)
        #expect(page.highlighted == nil)
        #expect(key(48, [])) // Tab from nothing: Back, Forward dimmed
        #expect(page.highlighted == arrows.back)
        #expect(key(49, [])) // Space: Back, to Behavior; the highlight stays on it
        #expect(sut.shownPage == .behavior && page.highlighted == arrows.back)
        // Right to left, Back is the right one.
        arrows.readsRightToLeft = { true }
        arrows.updateFrames()
        let backFrame = try #require(page.controls[arrows.back]?.frame), forwardFrame = try #require(page.controls[arrows.forward]?.frame)
        #expect(backFrame.minX > forwardFrame.minX)
        sut.close()
        #expect(arrows.ringWindow == nil)
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
        let first = try #require(sut.keys.page.highlighted)
        #expect(sut.handleKey(48, flags: [], windowNumber: window.windowNumber)) // Tab: the next control
        #expect(sut.keys.page.highlighted != first)
        #expect(sut.handleKey(48, flags: .shift, windowNumber: window.windowNumber)) // Shift-Tab: back
        #expect(sut.keys.page.highlighted == first)
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

    @Test("in Sound Sources' search, ↓ leaves it for the first app under it (N4), Tab for the stop after it, Shift-Tab, with Back and Forward dimmed, for the sidebar's last stop, from which Tab comes back into it (K3, R1), and Escape closes the search, from a row or the field")
    func searchKeys() async throws {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let apps = [AudioSource(id: "com.example.arc", name: "Arc"), AudioSource(id: "com.example.brave", name: "Brave")]
        preferences.recordSeen(apps)
        let model = SettingsModel.forTests(actions: actions, updates: updates, settings: UserSettings(preferences: preferences))
        model.state.status.seenApps = apps
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .soundSources)
        let window = try #require(sut.window)
        let typing = { () async throws -> Void in
            model.appList.search = ""
            await TestWait.until { window.contentView?.firstEditableTextField != nil }
            window.makeFirstResponder(try #require(window.contentView?.firstEditableTextField))
            try #require(window.firstResponder is NSText)
        }
        try await typing()
        await TestWait.until { sut.keys.page.rows.count >= 4 } // the sort, two apps, the buttons
        let first = try #require(model.appList.shownApps.first?.id)
        #expect(sut.handleKey(48, flags: .shift, windowNumber: window.windowNumber)) // Shift-Tab: the sidebar's last stop
        #expect(!(window.firstResponder is NSText) && sut.keys.sidebar.highlighted != nil && sut.keys.page.highlighted == nil)
        #expect(sut.handleKey(48, flags: [], windowNumber: window.windowNumber)) // Tab: back into the search
        #expect(window.firstResponder is NSText && !sut.keys.isLit)
        #expect(!sut.handleKey(123, flags: [], windowNumber: window.windowNumber)) // ←: the field's
        #expect(sut.handleKey(125, flags: [], windowNumber: window.windowNumber)) // ↓: the first app, not the sort beside it
        #expect(!(window.firstResponder is NSText))
        #expect(sut.keys.page.select())
        #expect(model.appList.selectedAppIDs == [first])
        #expect(sut.handleKey(53, flags: [], windowNumber: window.windowNumber)) // Escape, from the row
        #expect(model.appList.search == nil)

        try await typing()
        await TestWait.until { sut.keys.page.controls.contains { $0.value.tabOnly && $0.value.frame != .zero } } // the ✕
        #expect(sut.handleKey(48, flags: [], windowNumber: window.windowNumber)) // Tab: the stop after it, the ✕ (R1)
        #expect(!(window.firstResponder is NSText))
        let lit = try #require(sut.keys.page.highlighted)
        #expect(sut.keys.page.controls[lit]?.tabOnly == true && lit != sut.toolbarKeys.back && lit != sut.toolbarKeys.forward)
        #expect(model.appList.selectedAppIDs == [first]) // no row taken by it
        try await typing()
        #expect(sut.handleKey(53, flags: [], windowNumber: window.windowNumber)) // Escape, from the field
        #expect(model.appList.search == nil)
        #expect(!sut.handleKey(53, flags: [], windowNumber: window.windowNumber)) // no search open: not taken
    }

    @Test("on Sound Sources, Tab goes from Sort by to Reverse order, which Return presses, then to the magnifier; the open search's ✕ is a Tab stop too, before Sort by, and Return on it closes the search, while ↓ still goes from the field to the first app (R1, R3)")
    func soundSourcesHeaderByTab() async throws {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let apps = [AudioSource(id: "com.example.arc", name: "Arc"), AudioSource(id: "com.example.brave", name: "Brave")]
        preferences.recordSeen(apps)
        let model = SettingsModel.forTests(actions: actions, updates: updates, settings: UserSettings(preferences: preferences))
        model.state.status.seenApps = apps
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .soundSources)
        let window = try #require(sut.window)
        let page = sut.keys.page
        // Sort by, Reverse order, the magnifier; two apps; the bottom bar's two enabled buttons.
        await TestWait.until { page.rows.joined().count == 7 && !page.controls.values.contains { $0.frame == .zero } }
        let order = Array(page.rows.joined())
        let key = { (keyCode: UInt16, flags: NSEvent.ModifierFlags) in sut.handleKey(keyCode, flags: flags, windowNumber: window.windowNumber) }
        #expect(key(48, [])) // Tab: Sort by
        #expect(page.highlighted == order[0])
        #expect(key(48, [])) // Tab: Reverse order
        // Never Return on Sort by: its menu would wait for a click.
        try #require(page.highlighted == order[1])
        let wasReversed = model.appList.order.isReversed
        #expect(key(36, [])) // Return reverses the order
        #expect(model.appList.order.isReversed != wasReversed)
        #expect(key(48, [])) // Tab: the magnifier
        try #require(page.highlighted == order[2])
        #expect(key(36, [])) // Return opens the search
        #expect(model.appList.search != nil)
        // The search open: its ✕ in the magnifier's place, before Sort by.
        await TestWait.until {
            page.controls.contains { $0.value.tabOnly && ![sut.toolbarKeys.back, sut.toolbarKeys.forward].contains($0.key) }
                && page.rows.joined().count == 7 && page.rows.first?.count == 3
        }
        window.makeFirstResponder(nil)
        page.clear()
        #expect(key(125, [])) // ↓ from nothing: Sort by, past the ✕, as before
        #expect(page.highlighted == page.rows.first?[1])
        page.clear()
        #expect(key(48, [])) // Tab from nothing: the ✕
        let close = try #require(page.highlighted)
        try #require(close == page.rows.first?[0] && page.controls[close]?.tabOnly == true)
        #expect(key(36, [])) // Return closes the search
        #expect(model.appList.search == nil)
    }

    @Test("Tab's loop goes through Sound Sources in reading order: Back (over the page), then its open search, then the search's ✕; Shift-Tab the other way (the user's order, 2026-11-10: R1 had Tab from the search go up to Back)")
    func tabFromSearchInReadingOrder() async throws {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let apps = [AudioSource(id: "com.example.arc", name: "Arc"), AudioSource(id: "com.example.brave", name: "Brave")]
        preferences.recordSeen(apps)
        let model = SettingsModel.forTests(actions: actions, updates: updates, settings: UserSettings(preferences: preferences))
        model.state.status.seenApps = apps
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .general)
        sut.show(page: .soundSources) // Back goes to General; Forward dimmed
        let window = try #require(sut.window)
        let arrows = [sut.toolbarKeys.back, sut.toolbarKeys.forward]
        model.appList.search = ""
        await TestWait.until {
            sut.toolbarKeys.updateFrames() // as before each key
            return window.contentView?.firstEditableTextField != nil
                && sut.keys.page.controls[sut.toolbarKeys.back]?.isEnabled == true
                && sut.keys.page.controls.contains { $0.value.tabOnly && $0.value.frame != .zero && !arrows.contains($0.key) } // the ✕
        }
        window.makeFirstResponder(try #require(window.contentView?.firstEditableTextField))
        try #require(window.firstResponder is NSText)
        let key = { (keyCode: UInt16, flags: NSEvent.ModifierFlags) in sut.handleKey(keyCode, flags: flags, windowNumber: window.windowNumber) }
        #expect(key(48, [])) // Tab: the ✕ beside it
        let close = try #require(sut.keys.page.highlighted)
        #expect(sut.keys.page.controls[close]?.tabOnly == true && !arrows.contains(close))
        #expect(key(48, .shift)) // Shift-Tab: back into the search
        #expect(window.firstResponder is NSText && !sut.keys.isLit)
        #expect(key(48, .shift)) // Shift-Tab from it: Back, over it
        #expect(sut.keys.page.highlighted == sut.toolbarKeys.back && !(window.firstResponder is NSText))
        #expect(key(48, [])) // Tab from Back: the search (Forward dimmed)
        #expect(window.firstResponder is NSText && !sut.keys.isLit)
    }

    @Test("→ on a sidebar row Tab stopped on shows its page and goes into it, its first control lit once drawn (R3)")
    func rightOnTabbedSidebarRow() async throws {
        let sut = makeController()
        defer { sut.close() }
        sut.show(page: .general)
        let window = try #require(sut.window)
        await TestWait.until { sut.keys.sidebar.rows.count >= 2 && !sut.keys.page.rows.isEmpty }
        let key = { (keyCode: UInt16, flags: NSEvent.ModifierFlags) in sut.handleKey(keyCode, flags: flags, windowNumber: window.windowNumber) }
        #expect(key(123, [])) // ←: the sidebar, on General
        #expect(key(48, [])) // Tab: Media Player's row, its page not shown
        #expect(sut.shownPage == .general)
        #expect(key(124, [])) // →
        #expect(sut.shownPage == .mediaPlayer)
        await TestWait.until {
            sut.keys.page.highlighted.map { sut.keys.page.controls[$0] != nil } == true && sut.keys.sidebar.highlighted == nil
        }
        let lit = try #require(sut.keys.page.highlighted)
        #expect(sut.keys.page.controls[lit] != nil && sut.keys.side == .page)
    }

    @Test("as Tab lights Back or Forward, VoiceOver is told its name, once per arrival; a press on it, which keeps it lit, says nothing (R6)")
    func toolbarArrowsSayTheirNames() async throws {
        let sut = makeController()
        defer { sut.close() }
        sut.show()
        sut.show(page: .behavior)
        sut.show(page: .fineTuning)
        sut.show(page: .about)
        sut.goBack(nil) // on Fine-Tuning: Back and Forward both go somewhere
        let window = try #require(sut.window)
        let said = Locked<[String]>([])
        sut.toolbarKeys.announce = { said.append($0) }
        await TestWait.until {
            SettingsToolbarKeys.findArrows(in: window) != nil
                && sut.keys.page.controls.contains { !$0.value.tabOnly && $0.value.frame != .zero }
        }
        let key = { (keyCode: UInt16, flags: NSEvent.ModifierFlags) in sut.handleKey(keyCode, flags: flags, windowNumber: window.windowNumber) }
        #expect(key(48, [])) // Tab: Back
        #expect(key(48, [])) // Tab: Forward
        #expect(key(48, [])) // Tab: the page's first: nothing said
        #expect(key(48, .shift)) // Shift-Tab: Forward again
        #expect(said.value == [SettingsWindowController.backTitle, SettingsWindowController.forwardTitle, SettingsWindowController.forwardTitle])
        #expect(key(48, .shift)) // Back
        #expect(key(49, [])) // Space: Back, to Behavior, from where it still goes back: still lit
        #expect(sut.shownPage == .behavior && sut.keys.page.highlighted == sut.toolbarKeys.back)
        #expect(said.value.count == 4 && said.value.last == SettingsWindowController.backTitle)
    }

    @Test("Sound Sources' search taking the keyboard lets go of the keys' highlight: one focus at a time (the a11y audit's live check)")
    func searchTakesTheHighlight() async throws {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let apps = [AudioSource(id: "com.example.arc", name: "Arc"), AudioSource(id: "com.example.brave", name: "Brave")]
        preferences.recordSeen(apps)
        let model = SettingsModel.forTests(actions: actions, updates: updates, settings: UserSettings(preferences: preferences))
        model.state.status.seenApps = apps
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .soundSources)
        let window = try #require(sut.window)
        await TestWait.until { sut.keys.page.rows.count >= 3 }
        #expect(sut.handleKey(123, flags: [], windowNumber: window.windowNumber)) // ←: the sidebar, lit by the keys
        #expect(sut.keys.isLit)
        model.appList.search = ""
        await TestWait.until { window.contentView?.firstEditableTextField != nil }
        window.makeFirstResponder(try #require(window.contentView?.firstEditableTextField))
        await TestWait.until { !sut.keys.isLit }
        #expect(!sut.keys.isLit)
    }

    @Test("on Diagnostics, End reaches Show Logs… after every part, however far the form is scrolled (N3)")
    func diagnosticsButtonsLast() async throws {
        let model = makeModel()
        typealias Row = DiagnosticsSnapshot.Row
        let rows = (1...8).map { Row(label: "Fact \($0)", value: "Value") }
        let kinds: [DiagnosticsSnapshot.Section.Kind] = [.player, .behavior, .detection, .permissions, .autoHush, .mac]
        model.diagnostics = DiagnosticsSnapshot(
            overview: .init(kind: .working, title: "Working normally", detail: nil), apps: [], appsSummary: "None",
            sections: kinds.map { .init(kind: $0, title: "\($0)", summary: "Summary", rows: rows) }, text: "The report")
        let sut = makeController(model)
        defer { sut.close() }
        sut.show(page: .diagnostics)
        // Show Logs… and Copy Report side by side, last: both registered
        // and placed. Waiting for any three rows, the headings could come
        // first, End then reaching a heading, or Copy Report alone (M-1:
        // once, on macOS 15.7.7).
        await TestWait.until { sut.keys.page.rows.last?.count == 2 }
        #expect(sut.keys.handle(.end))
        #expect(sut.keys.handle(.returnKey))
        #expect(actions.log.calls.contains("showLogs"))
    }

    @Test("the window's Undo is Restore Defaults' and Sound Sources' removals' too, and forgets every step as the window closes")
    func undoClearedOnClose() throws {
        let model = makeModel()
        let sut = makeController(model)
        let window = try #require(sut.window)
        let undo = try #require(window.undoManager)
        #expect(model.undoManager === undo && model.appList.undoManager === undo)
        sut.show(page: .fineTuning)
        #expect(window.undoManager === undo)

        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        var timings = model.timings
        timings.startConfirmation = 2
        model.setTimings(timings)
        model.restoreDefaults(.timing)
        undo.endUndoGrouping()
        #expect(undo.canUndo)
        sut.close()
        #expect(!undo.canUndo && !undo.canRedo)
        sut.show() // opened again: the same, empty
        defer { sut.close() }
        #expect(window.undoManager === undo && !undo.canUndo)
    }
}
