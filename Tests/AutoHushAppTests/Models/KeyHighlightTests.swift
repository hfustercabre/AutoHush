import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The menu's highlight: reading order, the arrow keys wrapping, dimmed
/// controls skipped, the pointer moving it, pressing and adjusting.
@Suite("KeyHighlight", .waitsTimeLimit)
@MainActor
struct KeyHighlightTests {
    /// A control at `x`, `y` (44 × 22), counting its presses and adjustments.
    private func control(_ keyboard: KeyHighlight, _ x: CGFloat, _ y: CGFloat, enabled: Bool = true,
                         log: CallLog? = nil, name: String = "", adjusts: Bool = false) -> UUID {
        let id = UUID()
        keyboard.register(id, .init(frame: CGRect(x: x, y: y, width: 44, height: 22), isEnabled: enabled,
                                    press: { log?.calls.append("press \(name)") },
                                    adjust: adjusts ? { log?.calls.append("adjust \(name) \($0)") } : nil))
        return id
    }

    /// Its controls in reading order.
    private func order(_ keyboard: KeyHighlight) -> [UUID] { keyboard.rows.flatMap { $0 } }

    @Test("reading order: row by row from the top, a row being what's within 6 pt of its top (7 starts another), each left to right")
    func readingOrder() {
        let keyboard = KeyHighlight()
        let quit = control(keyboard, 260, 600)
        let settings = control(keyboard, 10, 606) // the same row as Quit: 6 pt under its top
        let below = control(keyboard, 0, 607) // 7 pt under that row's top: a row of its own
        let autoPause = control(keyboard, 280, 20)
        let fifteen = control(keyboard, 70, 101)
        let five = control(keyboard, 10, 100)
        #expect(keyboard.rows == [[autoPause], [five, fifteen], [settings, quit], [below]])
    }

    @Test("the keys go part by part: rows a scrolling middle hides come before the buttons pinned under it, whatever their frames")
    func parts() {
        let keyboard = KeyHighlight()
        let card = UUID(), hidden = UUID(), button = UUID()
        keyboard.register(button, .init(frame: CGRect(x: 0, y: 600, width: 80, height: 40), band: .bottom))
        // Scrolled out of view under the buttons, and in their row by its top.
        keyboard.register(hidden, .init(frame: CGRect(x: 0, y: 603, width: 300, height: 30)))
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 10, width: 300, height: 80), band: .top))
        #expect(keyboard.rows == [[card], [hidden], [button]])
    }

    @Test("↓ and ↑ go through every enabled control, wrapping at the ends; from nothing, ↓ is the first and ↑ the last")
    func moving() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0)
        _ = control(keyboard, 0, 50, enabled: false)
        let last = control(keyboard, 0, 100)
        keyboard.move(-1)
        #expect(keyboard.highlighted == last)
        keyboard.clear()
        keyboard.move(1)
        #expect(keyboard.highlighted == first)
        #expect(keyboard.revealed == first)
        keyboard.move(1) // the dimmed one is skipped
        #expect(keyboard.highlighted == last)
        keyboard.move(1)
        #expect(keyboard.highlighted == first)
        keyboard.move(-1)
        #expect(keyboard.highlighted == last)
        keyboard.clear()
        #expect(keyboard.highlighted == nil && keyboard.revealed == nil)
    }

    @Test("↓ and ↑ go row by row: from a row of one to a row's first, from a row of several to the nearest; ← and → move along a row, stopping at its ends")
    func rows() throws {
        let keyboard = MenuLikeRows.make()
        keyboard.k.move(1)
        #expect(keyboard.k.highlighted == keyboard.title)
        keyboard.k.move(1) // into the durations: the first
        #expect(keyboard.k.highlighted == keyboard.chips[0])
        try #require(keyboard.k.moveInRow(1))
        try #require(keyboard.k.moveInRow(1))
        #expect(keyboard.k.highlighted == keyboard.chips[2])
        keyboard.k.move(1) // under them, the toolbar: the nearest
        #expect(keyboard.k.highlighted == keyboard.toolbar[2])
        try #require(keyboard.k.moveInRow(-1))
        try #require(keyboard.k.moveInRow(-1))
        #expect(!keyboard.k.moveInRow(-1)) // the row's start
        keyboard.k.move(1) // wraps to the top
        #expect(keyboard.k.highlighted == keyboard.title)
        #expect(!keyboard.k.moveInRow(1)) // a row of one
    }

    @Test("Home and End go to the first and last row, without wrapping further; from nothing, Page Down is the first row and Page Up the last")
    func homeAndEnd() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0)
        _ = control(keyboard, 0, 30)
        let last = control(keyboard, 0, 60)
        _ = control(keyboard, 0, 90, enabled: false) // dimmed: skipped
        keyboard.jump(.last)
        #expect(keyboard.highlighted == last && keyboard.revealed == last)
        keyboard.jump(.last)
        #expect(keyboard.highlighted == last)
        keyboard.jump(.first)
        #expect(keyboard.highlighted == first)
        keyboard.clear()
        keyboard.jump(.pageDown)
        #expect(keyboard.highlighted == first)
        keyboard.clear()
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == last)
    }

    @Test("Page Down and Up go about a page (the rows that fit in `pageHeight` from where the highlight's row starts), at least a row, stopping at the ends; a row of several keeps the nearest")
    func pages() {
        let keyboard = KeyHighlight()
        keyboard.pageHeight = 100
        // Rows 22 pt tall every 30 pt: 0, 30, 60, 90, 120, 150, 180.
        let ids = (0..<7).map { control(keyboard, 0, CGFloat($0) * 30) }
        let right = control(keyboard, 200, 60) // beside the third
        keyboard.jump(.first)
        keyboard.jump(.pageDown) // 60 + 22 fits in 100 from 0, 90 + 22 doesn't
        #expect(keyboard.highlighted == ids[2])
        keyboard.jump(.pageDown) // 120 + 22 - 60 = 82 fits, 150's 112 doesn't
        #expect(keyboard.highlighted == ids[4])
        keyboard.jump(.pageDown)
        #expect(keyboard.highlighted == ids[6]) // the last: no wrapping
        keyboard.jump(.pageDown)
        #expect(keyboard.highlighted == ids[6])
        keyboard.jump(.pageUp) // 180 + 22 - 120 = 82 fits, 90 doesn't
        #expect(keyboard.highlighted == ids[4])
        keyboard.pageHeight = 10 // a page smaller than a row: still a row on
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == ids[3])
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == ids[2]) // a row of two, from one: its first
        _ = keyboard.moveInRow(1)
        #expect(keyboard.highlighted == right)
        keyboard.jump(.pageDown) // from a row of several: the nearest
        #expect(keyboard.highlighted == ids[3])
        keyboard.pageHeight = nil // all shows: a page is the whole part
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == ids[0])
    }

    @Test("Page Down and Up stay in their part (the menu's list) until its end, then step into the next part (its buttons) or the previous one (its card)")
    func pagesByPart() {
        let keyboard = KeyHighlight()
        keyboard.pageHeight = 1000
        let card = UUID(), button = UUID()
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 80), band: .top))
        let rows = (0..<3).map { index in
            let id = UUID()
            keyboard.register(id, .init(frame: CGRect(x: 0, y: 100 + CGFloat(index) * 30, width: 300, height: 22)))
            return id
        }
        keyboard.register(button, .init(frame: CGRect(x: 0, y: 200, width: 80, height: 22), band: .bottom))
        keyboard.jump(.first)
        #expect(keyboard.highlighted == card)
        keyboard.jump(.pageDown) // the card's part ends: into the list
        #expect(keyboard.highlighted == rows[0])
        keyboard.jump(.pageDown) // the list's end, not the buttons
        #expect(keyboard.highlighted == rows[2])
        keyboard.jump(.pageDown)
        #expect(keyboard.highlighted == button)
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == rows[2])
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == rows[0])
        keyboard.jump(.pageUp)
        #expect(keyboard.highlighted == card)
    }

    @Test("a key moving the highlight onto a control counts as its arrival (VoiceOver's cursor goes there); the pointer's doesn't")
    func arrivals() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0), second = control(keyboard, 0, 50)
        keyboard.move(1)
        keyboard.jump(.last)
        keyboard.jump(.first)
        #expect(keyboard.light(first).arrivals == 2 && keyboard.light(second).arrivals == 1)
        keyboard.hover(second, true)
        #expect(keyboard.highlighted == second && keyboard.light(second).arrivals == 1)
    }

    @Test("Zoom is told where the control a key moved to is on the screen, once it's scrolled into view; the pointer's moves aren't")
    func zoomFollows() async {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0)
        let told = Locked<[CGRect]>([])
        keyboard.screenFrame = { $0.offsetBy(dx: 1000, dy: 500) }
        keyboard.zoom = { rect in told.withLock { $0.append(rect) } }
        keyboard.move(1)
        #expect(told.value.isEmpty) // not before the reveal's scroll
        keyboard.update(first, frame: CGRect(x: 0, y: 10, width: 44, height: 22)) // scrolled
        await TestWait.until { !told.value.isEmpty }
        #expect(told.value == [CGRect(x: 1000, y: 510, width: 44, height: 22)])
        keyboard.clear()
        let second = control(keyboard, 0, 40)
        keyboard.hover(first, true)
        keyboard.move(1) // a key's move after the pointer's: told once it's scrolled into view
        await TestWait.until { told.value.count > 1 }
        // The pointer's move, though it came first, never was.
        #expect(told.value == [CGRect(x: 1000, y: 510, width: 44, height: 22), CGRect(x: 1000, y: 540, width: 44, height: 22)])
        #expect(keyboard.highlighted == second)
    }

    @Test("a side window opened by → lights its first row once its rows have come and been placed, waiting for frames that come after them")
    func firstWhenReady() async {
        let keyboard = KeyHighlight()
        keyboard.highlightFirstWhenReady()
        let second = UUID(), first = UUID()
        // Registered before they're placed, as rows appearing in the same update.
        keyboard.register(second, .init())
        keyboard.register(first, .init())
        await Task.yield()
        #expect(keyboard.highlighted == nil) // not placed yet: not lit at random
        keyboard.update(second, frame: CGRect(x: 0, y: 40, width: 100, height: 20))
        keyboard.update(first, frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        await TestWait.until { keyboard.highlighted != nil }
        #expect(keyboard.highlighted == first)
    }

    @Test("the pointer moves the highlight onto a control and takes it away as it leaves, never scrolling")
    func pointer() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0)
        let second = control(keyboard, 0, 50)
        keyboard.hover(second, true)
        #expect(keyboard.highlighted == second)
        #expect(keyboard.revealed == nil)
        keyboard.move(-1) // the keys go on from where the pointer is
        #expect(keyboard.highlighted == first)
        keyboard.hover(second, false) // no longer the highlighted one: nothing changes
        #expect(keyboard.highlighted == first)
        keyboard.hover(first, false)
        #expect(keyboard.highlighted == nil)
    }

    @Test("a control inside another (the card's Change Player row in the card) takes the highlight while the pointer is on it, whichever is told first, and gives it back to the one around it as the pointer leaves it")
    func nestedHover() {
        let keyboard = KeyHighlight()
        let card = UUID(), row = UUID()
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 0, width: 330, height: 140)))
        keyboard.register(row, .init(frame: CGRect(x: 12, y: 104, width: 306, height: 28)))
        keyboard.hover(card, true)
        #expect(keyboard.highlighted == card)
        keyboard.hover(row, true)
        #expect(keyboard.highlighted == row)
        keyboard.hover(row, false) // up onto the rest of the card
        #expect(keyboard.highlighted == card)

        // Into the row from outside the card: told in either order, the row's.
        keyboard.hover(card, false)
        #expect(keyboard.highlighted == nil)
        keyboard.hover(row, true)
        keyboard.hover(card, true)
        #expect(keyboard.highlighted == row)
        // Out of both, in either order: nothing.
        keyboard.hover(card, false)
        #expect(keyboard.highlighted == row)
        keyboard.hover(row, false)
        #expect(keyboard.highlighted == nil)
    }

    @Test("Return or Space presses the highlighted control, ← and → adjust it if it takes them; with none, nothing")
    func pressing() {
        let keyboard = KeyHighlight()
        let log = CallLog()
        let slider = control(keyboard, 0, 0, log: log, name: "slider", adjusts: true)
        let button = control(keyboard, 0, 50, log: log, name: "button")
        #expect(!keyboard.press())
        #expect(!keyboard.adjust(1))
        keyboard.hover(slider, true)
        #expect(keyboard.press())
        #expect(keyboard.adjust(-1))
        keyboard.hover(button, true)
        #expect(!keyboard.adjust(1))
        #expect(keyboard.press())
        #expect(log.calls == ["press slider", "adjust slider -1", "press button"])
    }

    @Test("a control dimmed or gone loses the highlight; a frame that came before it registered is kept")
    func changes() {
        let keyboard = KeyHighlight()
        let id = UUID()
        keyboard.update(id, frame: CGRect(x: 0, y: 30, width: 10, height: 10))
        keyboard.register(id, .init(press: {}, opensSide: true))
        let above = control(keyboard, 0, 0)
        #expect(order(keyboard) == [above, id])
        keyboard.hover(id, true)
        #expect(keyboard.highlightedOpensSide)
        keyboard.update(id, isEnabled: false)
        #expect(keyboard.highlighted == nil)
        #expect(order(keyboard) == [above])
        keyboard.update(id, isEnabled: true)
        keyboard.hover(id, true)
        keyboard.remove(id)
        #expect(keyboard.highlighted == nil)
        #expect(order(keyboard) == [above])
        keyboard.update(id, frame: CGRect(x: 0, y: 60, width: 10, height: 10)) // a frame after it went
        #expect(order(keyboard) == [above]) // makes up no control
    }

    @Test("a highlighted control dimmed or gone under the pointer gives the highlight to the one around it (the card's Try Again in the card), so Return presses that and ↓ goes on from it")
    func changesUnderPointer() {
        let keyboard = KeyHighlight()
        let card = UUID(), button = UUID()
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 0, width: 330, height: 140)))
        keyboard.register(button, .init(frame: CGRect(x: 12, y: 104, width: 80, height: 22)))
        keyboard.hover(card, true)
        keyboard.hover(button, true)
        #expect(keyboard.highlighted == button)
        keyboard.update(button, isEnabled: false) // dimmed, the pointer still on it
        #expect(keyboard.highlighted == card && keyboard.light(card).isOn)
        keyboard.update(button, isEnabled: true)
        keyboard.hover(button, true)
        #expect(keyboard.highlighted == button)
        keyboard.remove(button) // gone from under the pointer
        #expect(keyboard.highlighted == card && keyboard.light(card).isOn)
        keyboard.hover(card, false)
        #expect(keyboard.highlighted == nil)
    }

    @Test("each control's own light follows the highlight, so a move redraws the two it concerns")
    func lights() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0, 0), second = control(keyboard, 0, 50)
        let (one, two) = (keyboard.light(first), keyboard.light(second))
        keyboard.move(1)
        #expect(one.isOn && !two.isOn)
        keyboard.move(1)
        #expect(!one.isOn && two.isOn)
        keyboard.clear()
        #expect(!one.isOn && !two.isOn)
        keyboard.hover(first, true)
        #expect(keyboard.light(first) === one && one.isOn) // the same, kept while it's there
    }

    @Test("a press from the keys that removes its control (Restore Defaults) can leave the highlight on its card's first usable row, scrolled to")
    func pressMovesToGroupsFirst() async {
        let keyboard = KeyHighlight()
        let card = UUID(), other = UUID()
        let above = UUID(), dimmed = UUID(), firstUsable = UUID(), button = UUID()
        keyboard.register(above, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 22), group: other))
        keyboard.register(dimmed, .init(frame: CGRect(x: 0, y: 50, width: 300, height: 22), group: card, isEnabled: false))
        keyboard.register(firstUsable, .init(frame: CGRect(x: 0, y: 80, width: 300, height: 22), group: card))
        let pressing = Locked<Bool?>(nil)
        keyboard.register(button, .init(frame: CGRect(x: 200, y: 120, width: 80, height: 22), group: card, press: {
            pressing.withLock { $0 = keyboard.isPressing }
            keyboard.highlightFirst(in: card)
        }))
        keyboard.move(-1) // the button, last
        #expect(keyboard.highlighted == button)
        keyboard.press()
        keyboard.remove(button) // gone once pressed
        #expect(pressing.value == true)
        #expect(!keyboard.isPressing)
        await TestWait.until { keyboard.highlighted == firstUsable }
        #expect(keyboard.highlighted == firstUsable)
        #expect(keyboard.revealed == firstUsable)
    }
}
