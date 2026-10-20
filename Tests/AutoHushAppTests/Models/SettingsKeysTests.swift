import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp

/// Settings' highlight on its two sides: the arrows within a side, ← and →
/// between them, the sidebar showing each page at once, one highlight at a
/// time, and the keys a focused control keeps.
@Suite("SettingsKeys")
@MainActor
struct SettingsKeysTests {
    private final class Log { var calls: [String] = [] }

    /// Settings with a sidebar of `pages` (the shown one first) and a page of
    /// a switch row and a slider, as their views register them.
    private func makeKeys(log: Log, pages: [String] = ["General", "Detection"]) -> (SettingsKeys, rows: [UUID], controls: [UUID]) {
        let keys = SettingsKeys()
        var shown = pages[0]
        let rows = pages.enumerated().map { index, page in
            let id = UUID()
            keys.sidebar.register(id, .init(frame: CGRect(x: 0, y: CGFloat(index) * 30, width: 200, height: 28),
                                            press: { shown = page; log.calls.append("show \(page)") },
                                            isCurrent: { shown == page }))
            return id
        }
        let toggle = UUID(), slider = UUID()
        keys.page.register(toggle, .init(frame: CGRect(x: 0, y: 0, width: 400, height: 40), press: { log.calls.append("switch") }))
        keys.page.register(slider, .init(frame: CGRect(x: 0, y: 60, width: 400, height: 40), adjust: { log.calls.append("slider \($0)") }))
        return (keys, rows, [toggle, slider])
    }

    @Test("↓ and ↑ start in the page; Return or Space presses its control, ← and → change a slider and do nothing on another")
    func page() {
        let log = Log()
        let (keys, _, controls) = makeKeys(log: log)
        #expect(keys.handle(.down))
        #expect(keys.page.highlighted == controls[0])
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.right)) // a switch row takes no → : nothing happens, nothing beeps
        #expect(keys.handle(.down))
        #expect(keys.handle(.right))
        #expect(keys.handle(.left))
        #expect(keys.page.highlighted == controls[1])
        #expect(log.calls == ["switch", "slider 1", "slider -1"])
    }

    @Test("← goes to the sidebar, on the page shown; ↑ and ↓ there show each page at once; → or Return goes back into the page")
    func sides() {
        let log = Log()
        let (keys, rows, controls) = makeKeys(log: log)
        keys.handle(.down)
        #expect(keys.handle(.left)) // a switch row: ← goes to the sidebar
        #expect(keys.side == .sidebar)
        #expect(keys.sidebar.highlighted == rows[0])
        #expect(keys.page.highlighted == nil)
        #expect(keys.handle(.left)) // nothing further left
        #expect(keys.handle(.down))
        #expect(keys.sidebar.highlighted == rows[1])
        #expect(log.calls == ["show Detection"])
        #expect(keys.handle(.right))
        #expect(keys.side == .page)
        #expect(keys.page.highlighted == controls[0])
        #expect(keys.sidebar.highlighted == nil)
        keys.handle(.left)
        #expect(keys.sidebar.highlighted == rows[1])
        #expect(keys.handle(.returnKey)) // Return in the sidebar goes into the page too
        #expect(keys.page.highlighted == controls[0])
    }

    @Test("the pointer takes the highlight to its side, one at a time")
    func pointer() {
        let log = Log()
        let (keys, rows, controls) = makeKeys(log: log)
        keys.handle(.down)
        keys.sidebar.hover(rows[1], true)
        #expect(keys.side == .sidebar)
        #expect(keys.page.highlighted == nil)
        keys.page.hover(controls[1], true)
        #expect(keys.side == .page)
        #expect(keys.sidebar.highlighted == nil)
    }

    @Test("Tab leaves the keys to the keyboard's focus")
    func focus() {
        let log = Log()
        let (keys, _, _) = makeKeys(log: log)
        keys.handle(.down)
        #expect(!keys.handle(.tab))
        #expect(keys.page.highlighted == nil && keys.sidebar.highlighted == nil)
    }

    @Test("a control with the focus keeps Return, Space, ← and → even while the pointer highlights another, as in the menu")
    func focusKeepsKeys() {
        let log = Log()
        let (keys, _, controls) = makeKeys(log: log)
        keys.page.hover(controls[0], true) // the pointer rests on the switch row
        for key: HighlightKey in [.left, .right, .returnKey, .space] {
            #expect(!keys.handle(key, controlHasFocus: true), "\(key)")
        }
        #expect(log.calls.isEmpty)
        #expect(keys.handle(.space)) // no focus: the row the pointer is on
        #expect(log.calls == ["switch"])
    }

    @Test("← with nothing highlighted and no focus goes to the sidebar, on the page shown; clear() brings the keys back to the page")
    func leftFromNothing() {
        let log = Log()
        let (keys, rows, _) = makeKeys(log: log)
        #expect(keys.handle(.left))
        #expect(keys.side == .sidebar && keys.sidebar.highlighted == rows[0])
        keys.clear()
        #expect(keys.side == .page && keys.sidebar.highlighted == nil)
    }

    @Test("once the sidebar lets go of the highlight (the pointer left it, Tab), ↓ moves in the page, never showing the first page by itself")
    func sidebarLetGo() {
        let log = Log()
        let (keys, rows, controls) = makeKeys(log: log)
        keys.sidebar.hover(rows[1], true)
        keys.sidebar.hover(rows[1], false) // the pointer went on, into the page
        #expect(keys.handle(.down))
        #expect(keys.page.highlighted == controls[0])
        #expect(log.calls.isEmpty) // no page shown
        keys.sidebar.hover(rows[0], true)
        #expect(!keys.handle(.tab))
        #expect(keys.handle(.down))
        #expect(keys.side == .page && keys.page.highlighted == controls[0] && log.calls.isEmpty)
    }

    @Test("keys with nothing to act on do nothing, without a beep: Return with nothing highlighted, → on a row that takes none")
    func silent() {
        let log = Log()
        let (keys, _, _) = makeKeys(log: log)
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.right))
        #expect(log.calls.isEmpty)
    }
}
