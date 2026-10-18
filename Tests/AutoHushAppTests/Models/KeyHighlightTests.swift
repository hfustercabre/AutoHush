import Foundation
import Testing
@testable import AutoHushApp

/// The menu's highlight: reading order, the arrow keys wrapping, dimmed
/// controls skipped, the pointer moving it, pressing and adjusting.
@Suite("KeyHighlight")
@MainActor
struct KeyHighlightTests {
    /// A control at `x`, `y` (44 × 22), counting its presses and adjustments.
    private func control(_ keyboard: KeyHighlight, _ x: CGFloat, _ y: CGFloat, enabled: Bool = true,
                         log: Log? = nil, name: String = "", adjusts: Bool = false) -> UUID {
        let id = UUID()
        keyboard.register(id, .init(frame: CGRect(x: x, y: y, width: 44, height: 22), isEnabled: enabled,
                                    press: { log?.calls.append("press \(name)") },
                                    adjust: adjusts ? { log?.calls.append("adjust \(name) \($0)") } : nil))
        return id
    }

    private final class Log { var calls: [String] = [] }

    @Test("reading order: row by row from the top, a row being what's within 6 pt of its top, each left to right")
    func order() {
        let keyboard = KeyHighlight()
        let quit = control(keyboard, 260, 600)
        let settings = control(keyboard, 10, 602) // the same row as Quit
        let autoPause = control(keyboard, 280, 20)
        let fifteen = control(keyboard, 70, 101)
        let five = control(keyboard, 10, 100)
        #expect(keyboard.order == [autoPause, five, fifteen, settings, quit])
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
    func rows() {
        let keyboard = MenuKeyboardRows.make()
        keyboard.k.move(1)
        #expect(keyboard.k.highlighted == keyboard.title)
        keyboard.k.move(1) // into the durations: the first
        #expect(keyboard.k.highlighted == keyboard.chips[0])
        #expect(keyboard.k.moveInRow(1) && keyboard.k.moveInRow(1))
        #expect(keyboard.k.highlighted == keyboard.chips[2])
        keyboard.k.move(1) // under them, the toolbar: the nearest
        #expect(keyboard.k.highlighted == keyboard.toolbar[2])
        #expect(keyboard.k.moveInRow(-1) && keyboard.k.moveInRow(-1))
        #expect(!keyboard.k.moveInRow(-1)) // the row's start
        keyboard.k.move(1) // wraps to the top
        #expect(keyboard.k.highlighted == keyboard.title)
        #expect(!keyboard.k.moveInRow(1)) // a row of one
    }

    @Test("a side window opened by → lights its first row once its rows have come")
    func firstWhenReady() async {
        let keyboard = KeyHighlight()
        keyboard.highlightFirstWhenReady()
        let second = UUID(), first = UUID()
        keyboard.register(second, .init(frame: CGRect(x: 0, y: 40, width: 100, height: 20)))
        keyboard.register(first, .init(frame: CGRect(x: 0, y: 0, width: 100, height: 20)))
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
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

    @Test("Return or Space presses the highlighted control, ← and → adjust it if it takes them; with none, nothing")
    func pressing() {
        let keyboard = KeyHighlight()
        let log = Log()
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
        #expect(keyboard.order == [above, id])
        keyboard.hover(id, true)
        #expect(keyboard.highlightedOpensSide)
        keyboard.update(id, isEnabled: false)
        #expect(keyboard.highlighted == nil)
        #expect(keyboard.order == [above])
        keyboard.update(id, isEnabled: true)
        keyboard.hover(id, true)
        keyboard.remove(id)
        #expect(keyboard.highlighted == nil)
        #expect(keyboard.order == [above])
    }
}

/// A menu-like layout: a title, five durations in a row, four buttons in a row.
@MainActor
private enum MenuKeyboardRows {
    static func make() -> (k: KeyHighlight, title: UUID, chips: [UUID], toolbar: [UUID]) {
        let k = KeyHighlight()
        let title = UUID()
        k.register(title, .init(frame: CGRect(x: 0, y: 0, width: 345, height: 20)))
        let chips = (0..<5).map { i -> UUID in
            let id = UUID()
            k.register(id, .init(frame: CGRect(x: 14 + CGFloat(i) * 65, y: 40, width: 60, height: 30)))
            return id
        }
        let toolbar = (0..<4).map { i -> UUID in
            let id = UUID()
            k.register(id, .init(frame: CGRect(x: 8 + CGFloat(i) * 82, y: 100, width: 80, height: 40)))
            return id
        }
        return (k, title, chips, toolbar)
    }
}
