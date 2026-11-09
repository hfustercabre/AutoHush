import AppKit
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
    /// Settings with a sidebar of `pages` (the shown one first) and a page of
    /// a switch row and a slider, as their views register them.
    private func makeKeys(log: CallLog, pages: [String] = ["General", "Detection"]) -> (SettingsKeys, rows: [UUID], controls: [UUID]) {
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

    @Test("on a row that selects (Sound Sources' apps), Return presses it (its switch) and Space selects it; elsewhere Space presses, as Return")
    func spaceSelects() {
        let log = CallLog()
        let (keys, _, controls) = makeKeys(log: log)
        let app = UUID()
        keys.page.register(app, .init(frame: CGRect(x: 0, y: 120, width: 400, height: 40),
                                      press: { log.calls.append("switch app") }, select: { log.calls.append("select app") }))
        keys.page.hover(app, true)
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.space))
        keys.page.hover(app, false)
        keys.page.hover(controls[0], true)
        #expect(keys.handle(.space))
        #expect(log.calls == ["switch app", "select app", "switch"])
    }

    @Test("Delete removes the highlighted control that can be removed (an added app's tile); on another, or with none, it isn't taken")
    func delete() {
        let log = CallLog()
        let (keys, _, _) = makeKeys(log: log)
        let tile = UUID()
        keys.page.register(tile, .init(frame: CGRect(x: 0, y: 120, width: 120, height: 44), delete: { log.calls.append("remove") }))
        #expect(!keys.handle(.delete)) // nothing highlighted
        #expect(keys.handle(.down))
        #expect(!keys.handle(.delete)) // the switch row takes none
        #expect(keys.handle(.down) && keys.handle(.down))
        #expect(keys.page.highlighted == tile)
        #expect(keys.handle(.delete))
        #expect(log.calls == ["remove"])
        #expect(HighlightKey(keyCode: 51, modifiers: []) == .delete && HighlightKey(keyCode: 117, modifiers: []) == .delete)
    }

    @Test("the highlight goes to the first control, in reading order, of those that stand for what's shown (a Fine-Tuning card's rows), skipping a dimmed one")
    func highlightCurrent() {
        let keys = SettingsKeys()
        let ids = (0..<4).map { _ in UUID() }
        // Registered out of order; the first of the card's rows is dimmed.
        keys.page.register(ids[3], .init(frame: CGRect(x: 0, y: 180, width: 400, height: 40), isCurrent: { true }))
        keys.page.register(ids[2], .init(frame: CGRect(x: 0, y: 120, width: 400, height: 40), isCurrent: { true }))
        keys.page.register(ids[1], .init(frame: CGRect(x: 0, y: 60, width: 400, height: 40), isEnabled: false, isCurrent: { true }))
        keys.page.register(ids[0], .init(frame: CGRect(x: 0, y: 0, width: 400, height: 40), isCurrent: { false }))
        keys.page.highlightCurrent()
        #expect(keys.page.highlighted == ids[2])
    }

    @Test("↓ and ↑ start in the page; Return or Space presses its control, ← and → change a slider and do nothing on another")
    func page() {
        let log = CallLog()
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
        let log = CallLog()
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

    @Test("End and Home jump through the page; in the sidebar, they show the last and first page at once, as ↑ and ↓ do")
    func jumps() {
        let log = CallLog()
        let (keys, rows, controls) = makeKeys(log: log, pages: ["General", "Detection", "About"])
        #expect(keys.handle(.end))
        #expect(keys.side == .page && keys.page.highlighted == controls[1])
        #expect(keys.handle(.home, controlHasFocus: true)) // a focused control doesn't keep them
        #expect(keys.page.highlighted == controls[0])
        keys.handle(.left)
        #expect(keys.handle(.end))
        #expect(keys.sidebar.highlighted == rows[2])
        #expect(keys.handle(.pageUp)) // the sidebar all shows: a page is all of it
        #expect(keys.sidebar.highlighted == rows[0])
        #expect(log.calls == ["show About", "show General"])
        #expect(keys.page.highlighted == nil)
    }

    @Test("the pointer takes the highlight to its side, one at a time")
    func pointer() {
        let log = CallLog()
        let (keys, rows, controls) = makeKeys(log: log)
        keys.handle(.down)
        keys.sidebar.hover(rows[1], true)
        #expect(keys.side == .sidebar)
        #expect(keys.page.highlighted == nil)
        keys.page.hover(controls[1], true)
        #expect(keys.side == .page)
        #expect(keys.sidebar.highlighted == nil)
    }

    @Test("Tab and Shift-Tab stop at every control of the page, a row's one after the other, wrapping (B, the user, 2026-11-09); ↓ goes by row")
    func tab() {
        let log = CallLog()
        let (keys, _, controls) = makeKeys(log: log)
        let beside = UUID() // in the switch's row, to its right
        keys.page.register(beside, .init(frame: CGRect(x: 410, y: 0, width: 80, height: 40)))
        #expect(keys.handle(.tab))
        #expect(keys.page.highlighted == controls[0])
        #expect(keys.handle(.tab))
        #expect(keys.page.highlighted == beside)
        #expect(keys.handle(.tab))
        #expect(keys.page.highlighted == controls[1])
        #expect(keys.handle(.tab)) // wraps
        #expect(keys.page.highlighted == controls[0])
        #expect(keys.handle(.backTab))
        #expect(keys.page.highlighted == controls[1])
        #expect(keys.handle(.backTab))
        #expect(keys.page.highlighted == beside)
        keys.page.clear()
        keys.handle(.down)
        keys.handle(.down) // by row: past the one beside
        #expect(keys.page.highlighted == controls[1])
    }

    @Test("Tab stays in the side that has the highlight: in the sidebar it goes page by page, each shown at once, as ↓")
    func tabInSidebar() {
        let log = CallLog()
        let (keys, rows, _) = makeKeys(log: log)
        keys.handle(.down)
        keys.handle(.left) // into the sidebar
        #expect(keys.side == .sidebar)
        let lit = keys.sidebar.highlighted
        #expect(lit != nil)
        log.calls.removeAll()
        #expect(keys.handle(.tab))
        #expect(keys.side == .sidebar && keys.page.highlighted == nil)
        #expect(keys.sidebar.highlighted != lit && rows.contains { $0 == keys.sidebar.highlighted })
        #expect(log.calls.count == 1 && log.calls[0].hasPrefix("show "))
    }

    @Test("a control with the focus keeps Return, Space, ← and → while nothing is highlighted; once something is, its tint hides the focus's and it takes them (N6)")
    func focusKeepsKeysUntilSomethingIsLit() {
        let log = CallLog()
        let (keys, _, controls) = makeKeys(log: log)
        for key: HighlightKey in [.left, .right, .returnKey, .space] {
            #expect(!keys.handle(key, controlHasFocus: true), "\(key)")
        }
        #expect(log.calls.isEmpty && !keys.isLit)
        keys.page.hover(controls[0], true) // the pointer rests on the switch row
        #expect(keys.isLit)
        #expect(keys.handle(.space, controlHasFocus: true)) // the row the pointer is on, not the hidden focus
        keys.page.hover(controls[0], false)
        keys.page.hover(controls[1], true) // the slider
        #expect(keys.handle(.right, controlHasFocus: true))
        #expect(log.calls == ["switch", "slider 1"])
    }

    @Test("a click on a sidebar row the pointer rests on keeps the pointer's look, the keys' outline and VoiceOver's cursor left alone; Back or Forward moves the keys' highlight with the page (N1)")
    func clickedRowKeepsThePointersLook() {
        let keys = SettingsKeys()
        var shown = "General"
        let general = UUID(), detection = UUID()
        keys.sidebar.register(general, .init(frame: CGRect(x: 0, y: 0, width: 200, height: 28),
                                             press: { shown = "General" }, isCurrent: { shown == "General" }))
        keys.sidebar.register(detection, .init(frame: CGRect(x: 0, y: 30, width: 200, height: 28),
                                               press: { shown = "Detection" }, isCurrent: { shown == "Detection" }))
        keys.sidebar.hover(detection, true)
        #expect(keys.sidebar.press()) // the click: its page shows
        keys.pageChanged()
        #expect(shown == "Detection" && keys.sidebar.highlighted == detection)
        #expect(!keys.sidebar.light(detection).byKeys && keys.sidebar.light(detection).arrivals == 0)
        keys.sidebar.hover(detection, false)
        // The keys on the sidebar (from the page, ←), then Back: the highlight follows the page.
        keys.page.register(UUID(), .init(frame: CGRect(x: 0, y: 0, width: 400, height: 40), press: {}))
        #expect(keys.handle(.down) && keys.handle(.left))
        #expect(keys.sidebar.highlighted == detection && keys.sidebar.isLitByKeys)
        shown = "General"
        keys.pageChanged()
        #expect(keys.sidebar.highlighted == general && keys.sidebar.isLitByKeys)
    }

    @Test("the sidebar's link at its foot: ↓ stops on it without opening it, Return or Space opens it, ↓ goes on round to the first page (N7)")
    func sidebarLink() {
        let log = CallLog()
        let (keys, rows, controls) = makeKeys(log: log)
        let link = UUID()
        keys.sidebar.register(link, .init(frame: CGRect(x: 60, y: 600, width: 120, height: 18), band: .bottom,
                                          press: { log.calls.append("open link") }))
        keys.handle(.left) // the sidebar, on General
        keys.handle(.down)
        #expect(keys.handle(.down))
        #expect(keys.sidebar.highlighted == link)
        #expect(log.calls == ["show Detection"]) // the link not opened
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.space))
        #expect(keys.sidebar.highlighted == link && keys.page.highlighted == nil)
        #expect(keys.handle(.end)) // already the last
        #expect(keys.handle(.down))
        #expect(keys.sidebar.highlighted == rows[0])
        #expect(log.calls == ["show Detection", "open link", "open link", "show General"])
        #expect(keys.handle(.right)) // a page's row: into the page
        #expect(keys.page.highlighted == controls[0])
    }

    @Test("← with nothing highlighted and no focus goes to the sidebar, on the page shown; clear() brings the keys back to the page")
    func leftFromNothing() {
        let log = CallLog()
        let (keys, rows, _) = makeKeys(log: log)
        #expect(keys.handle(.left))
        #expect(keys.side == .sidebar && keys.sidebar.highlighted == rows[0])
        keys.clear()
        #expect(keys.side == .page && keys.sidebar.highlighted == nil)
    }

    @Test("once the sidebar lets go of the highlight (the pointer left it), ↓ moves in the page, never showing the first page by itself")
    func sidebarLetGo() {
        let log = CallLog()
        let (keys, rows, controls) = makeKeys(log: log)
        keys.sidebar.hover(rows[1], true)
        keys.sidebar.hover(rows[1], false) // the pointer went on, into the page
        #expect(keys.handle(.down))
        #expect(keys.page.highlighted == controls[0])
        #expect(log.calls.isEmpty) // no page shown
        keys.sidebar.hover(rows[0], true)
        keys.sidebar.hover(rows[0], false)
        #expect(keys.handle(.down))
        #expect(keys.side == .page && keys.page.highlighted == controls[0] && log.calls.isEmpty)
    }

    @Test("keys with nothing to act on do nothing, without a beep: Return with nothing highlighted, → on a row that takes none")
    func silent() {
        let log = CallLog()
        let (keys, _, _) = makeKeys(log: log)
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.right))
        #expect(log.calls.isEmpty)
    }
}
