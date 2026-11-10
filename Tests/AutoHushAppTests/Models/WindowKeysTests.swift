import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp

/// The keys of the windows that guide the user (A4c): Settings' with one
/// side, Return always the main button's (R2), Space the lit control's, a
/// letter typed into the welcome's search (T1), ↓ out of a text field and
/// ↑ left to it, and the keys a focused control keeps.
@Suite("WindowKeys")
@MainActor
struct WindowKeysTests {
    /// A window's keys over two tiles side by side, then a button under them,
    /// as their views register them; what the window is asked, in `log`.
    private func makeKeys(log: CallLog) -> (WindowKeys, tiles: [UUID], button: UUID) {
        let keys = WindowKeys()
        keys.dropFocus = { log.calls.append("drop focus") }
        let tiles = [UUID(), UUID()]
        for (index, tile) in tiles.enumerated() {
            keys.highlight.register(tile, .init(frame: CGRect(x: CGFloat(index) * 130, y: 0, width: 120, height: 44),
                                                press: { log.calls.append("tile \(index)") }))
        }
        let button = UUID()
        keys.highlight.register(button, .init(frame: CGRect(x: 300, y: 100, width: 80, height: 28), band: .bottom,
                                              press: { log.calls.append("button") }))
        return (keys, tiles, button)
    }

    @Test("↑ and ↓ move row by row, the focus let go first; ← and → along a row; Space presses what's lit")
    func moves() {
        let log = CallLog()
        let (keys, tiles, button) = makeKeys(log: log)
        #expect(keys.handle(.down))
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(keys.handle(.right))
        #expect(keys.highlight.highlighted == tiles[1])
        #expect(keys.handle(.right)) // the row's end: nothing, no beep
        #expect(keys.highlight.highlighted == tiles[1])
        #expect(keys.handle(.space))
        #expect(keys.handle(.down))
        #expect(keys.highlight.highlighted == button)
        #expect(keys.handle(.home))
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(log.calls == ["drop focus", "tile 1", "drop focus", "drop focus"])
    }

    @Test("Return is left to the main button whatever is lit, and does nothing while it's dimmed or gone (R2); Space with nothing lit does nothing")
    func returnKey() {
        let log = CallLog()
        let (keys, _, _) = makeKeys(log: log)
        #expect(keys.handle(.returnKey)) // no main button: nothing, no beep
        #expect(keys.handle(.space)) // nothing lit: nothing
        let main = UUID(), other = UUID()
        keys.mainButton(main, isEnabled: false)
        #expect(keys.handle(.returnKey)) // dimmed: nothing
        keys.mainButton(other, isEnabled: true)
        keys.mainButton(main, isEnabled: true)
        #expect(!keys.handle(.returnKey)) // the window's, so its main button's
        keys.mainButton(other, isEnabled: nil)
        keys.handle(.down)
        #expect(!keys.handle(.returnKey)) // a tile lit: still the main button's
        keys.mainButton(main, isEnabled: nil)
        #expect(keys.handle(.returnKey))
        #expect(keys.handle(.space)) // presses the lit tile
        #expect(log.calls == ["drop focus", "tile 0"])
    }

    @Test("in a window with no main button (the logs), Return presses the lit control, as in Settings; ↑ and ↓ scroll a list that's one stop until its end, then move on (R6)")
    func returnPressesAndListScrolls() {
        let log = CallLog()
        let (keys, _, button) = makeKeys(log: log)
        keys.returnPresses = true
        var scrolled = 0
        let list = UUID()
        keys.highlight.register(list, .init(frame: CGRect(x: 0, y: 50, width: 300, height: 40), scroll: { step in
            guard scrolled + step <= 2 else { return false } // two steps from its end
            scrolled += step
            return true
        }))
        #expect(keys.handle(.returnKey)) // nothing lit: nothing, no beep
        keys.handle(.down)
        #expect(keys.handle(.returnKey))
        #expect(log.calls.last == "tile 0")
        keys.handle(.down)
        #expect(keys.highlight.highlighted == list)
        keys.handle(.down)
        keys.handle(.down)
        #expect(keys.highlight.highlighted == list && scrolled == 2)
        keys.handle(.down) // at its end: on to the next row
        #expect(keys.highlight.highlighted == button)
        keys.handle(.up)
        keys.handle(.up) // back on the list, it scrolls up
        #expect(keys.highlight.highlighted == list && scrolled == 1)
    }

    @Test("a focused control keeps Return, Space, ← and → while nothing is lit; a lit one, whose tint hides the focus's, takes them, the focus let go (N6); the arrows move the highlight")
    func focusedControl() {
        let log = CallLog()
        let (keys, tiles, _) = makeKeys(log: log)
        for key: HighlightKey in [.returnKey, .space, .left, .right] { #expect(!keys.handle(key, focus: .control)) }
        #expect(log.calls.isEmpty)
        #expect(keys.handle(.down, focus: .control)) // the arrows move the highlight
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(keys.handle(.right, focus: .control)) // along the lit row
        #expect(keys.highlight.highlighted == tiles[1])
        #expect(keys.handle(.space, focus: .control)) // the lit tile, not the hidden focus
        #expect(log.calls == ["drop focus", "drop focus", "drop focus", "tile 1"])
    }

    @Test("Tab and Shift-Tab stop at every control, a row's tiles one after the other, wrapping, the focus let go (B, the user, 2026-11-09)")
    func tab() {
        let log = CallLog()
        let (keys, tiles, button) = makeKeys(log: log)
        #expect(keys.handle(.tab, focus: .control))
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(keys.handle(.tab))
        #expect(keys.highlight.highlighted == tiles[1]) // ↓ would go to the button
        #expect(keys.handle(.tab))
        #expect(keys.highlight.highlighted == button)
        #expect(keys.handle(.tab)) // wraps
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(keys.handle(.backTab))
        #expect(keys.highlight.highlighted == button)
        keys.highlight.clear()
        #expect(keys.handle(.backTab)) // from nothing: the last
        #expect(keys.highlight.highlighted == button)
        #expect(log.calls == Array(repeating: "drop focus", count: 6))
    }

    @Test("Tab comes round to the window's search, as macOS's key loop goes into a field: Shift-Tab from the first control, Tab from the last, the highlight let go (K3); without one showing, round")
    func tabIntoSearch() {
        let log = CallLog()
        let (keys, tiles, button) = makeKeys(log: log)
        keys.focusSearch = { log.calls.append("search"); return true }
        #expect(keys.handle(.tab))
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(keys.handle(.backTab)) // before the first: the search
        #expect(keys.highlight.highlighted == nil)
        #expect(keys.handle(.backTab, focus: .textField)) // out of it, back: the last
        #expect(keys.highlight.highlighted == button)
        #expect(keys.handle(.tab)) // past the last: the search
        #expect(keys.highlight.highlighted == nil)
        #expect(log.calls == ["drop focus", "search", "drop focus", "search"])
        keys.focusSearch = { false }
        #expect(keys.handle(.backTab, focus: .textField) && keys.handle(.tab))
        #expect(keys.highlight.highlighted == tiles[0])
    }

    @Test("with a control focused and nothing lit (Add an App's step, with keyboard navigation on), Tab and ↓ go on from it, not from the top (W9)")
    func movesOnFromTheFocus() {
        let log = CallLog()
        let (keys, tiles, button) = makeKeys(log: log)
        keys.highlight.focus(tiles[1], true)
        #expect(keys.handle(.tab, focus: .control))
        #expect(keys.highlight.highlighted == button)
        keys.highlight.clear()
        #expect(keys.handle(.down, focus: .control))
        #expect(keys.highlight.highlighted == button)
        #expect(log.calls == ["drop focus", "drop focus"])
    }

    @Test("in a text field, typing and ↑ stay the field's; ↓ or Tab leaves it for the first row, whatever was lit, Shift-Tab for the last control (K3)")
    func textField() {
        let log = CallLog()
        let (keys, tiles, button) = makeKeys(log: log)
        keys.highlight.hover(button, true)
        for key: HighlightKey in [.up, .returnKey, .space, .left, .right, .home, .delete] {
            #expect(!keys.handle(key, focus: .textField))
        }
        #expect(keys.highlight.highlighted == button)
        #expect(keys.handle(.down, focus: .textField))
        #expect(keys.highlight.highlighted == tiles[0])
        keys.highlight.hover(button, true)
        #expect(keys.handle(.tab, focus: .textField)) // Tab: the same
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(log.calls == ["drop focus", "drop focus"]) // Return was the field's
        #expect(keys.handle(.backTab, focus: .textField)) // Shift-Tab: the last control
        #expect(keys.highlight.highlighted == button)
        // Right to left, Tab's first is the row's right end; ↓'s stays.
        keys.highlight.readsRightToLeft = { true }
        #expect(keys.handle(.tab, focus: .textField))
        #expect(keys.highlight.highlighted == tiles[1])
        #expect(keys.handle(.down, focus: .textField))
        #expect(keys.highlight.highlighted == tiles[0])
    }

    @Test("a letter typed while something is lit goes to the search, the highlight let go (T1); not without one lit, a search or in a field")
    func typing() {
        let log = CallLog()
        let (keys, tiles, _) = makeKeys(log: log)
        keys.typed() // no search: nothing
        keys.focusSearch = { log.calls.append("search"); return true }
        keys.typed() // nothing lit: the letter is the window's
        keys.handle(.down)
        keys.typed(focus: .textField) // already typing
        #expect(keys.highlight.highlighted == tiles[0])
        keys.typed()
        #expect(keys.highlight.highlighted == nil)
        // Then ↓ from the search: into the tiles again.
        #expect(keys.handle(.down, focus: .textField))
        #expect(keys.highlight.highlighted == tiles[0])
        #expect(log.calls == ["drop focus", "search", "drop focus"])
    }

    @Test("a search that doesn't show leaves the highlight where it is")
    func noSearchShown() {
        let log = CallLog()
        let (keys, tiles, _) = makeKeys(log: log)
        keys.focusSearch = { false }
        keys.handle(.down)
        keys.typed()
        #expect(keys.highlight.highlighted == tiles[0])
    }

    @Test("what counts as typed: what a field would show, without ⌘, ⌥ or ⌃")
    func typed() {
        #expect(WindowKeys.isTyped("a", modifiers: []))
        #expect(WindowKeys.isTyped("A", modifiers: .shift))
        #expect(WindowKeys.isTyped("é", modifiers: []))
        #expect(!WindowKeys.isTyped("a", modifiers: .command))
        #expect(!WindowKeys.isTyped("a", modifiers: .option))
        #expect(!WindowKeys.isTyped("\u{1B}", modifiers: [])) // Escape
        #expect(!WindowKeys.isTyped("\u{F700}", modifiers: [])) // ↑
        #expect(!WindowKeys.isTyped("", modifiers: []))
        #expect(!WindowKeys.isTyped(nil, modifiers: []))
    }
}
