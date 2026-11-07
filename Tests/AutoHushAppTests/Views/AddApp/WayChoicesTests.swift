import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers

/// Add an App's way cards and the keys (KB2a, the a11y audit's KB2, the
/// user's pick, 2026-11-06): out of the keys' reach before, a keyboard user
/// could only take the recommended way.
@Suite("Add an App's way cards", .waitsTimeLimit, .application)
@MainActor
struct WayChoicesTests {
    @Test("each card the check left to choose takes the keys' highlight, as the players' tiles do, and Space on one chooses it; the ways that can't be chosen don't")
    func cardsTakeTheKeys() async throws {
        let found = CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .page, mark: .none),
                   CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback"), .panel(rememberedRow: nil)]))
        let world = World()
        let model = await AddAppModel.ready(on: world)
        defer { model.windowClosed() }
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(found))
        await TestWait.until { model.result != nil }
        #expect(model.choosableWays == [.menu, .panel] && model.chosenWay == .menu)

        let keys = WindowKeys()
        // Moved by the keys alone: the pointer, resting wherever the window
        // opens (a VoiceOver check left it at the screen's corner), would
        // light the first card (T-5).
        keys.highlight.followsPointer = false
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: AddAppView.width, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: WayChoices(model: model, result: found, app: "Player").windowKeys(keys))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        await TestWait.until { keys.highlight.rows.joined().count == 2 } // the two cards, not the page's way
        #expect(keys.highlight.rows.count == 2) // one under the other: ↑ and ↓ step through them
        #expect(keys.highlight.highlighted == nil)

        #expect(keys.handle(.down)) // the menu's card, the recommended one
        #expect(keys.handle(.down)) // the panel's
        // The button's press, as SwiftUI triggers it, may land after the key.
        #expect(keys.handle(.space))
        await TestWait.until { model.chosenWay == .panel }
        #expect(model.chosenWay == .panel)
        #expect(keys.handle(.up))
        #expect(keys.handle(.space))
        await TestWait.until { model.chosenWay == .menu }
        #expect(model.chosenWay == .menu)
    }
}
