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

    @Test("a focused control keeps Return, Space, ← and →; the arrows, Tab too, move the highlight")
    func focusedControl() {
        let log = CallLog()
        let (keys, _, _) = makeKeys(log: log)
        keys.handle(.down)
        for key: HighlightKey in [.returnKey, .space, .left, .right] { #expect(!keys.handle(key, focus: .control)) }
        #expect(keys.handle(.down, focus: .control)) // the arrows still move the highlight
        #expect(keys.highlight.highlighted != nil)
        #expect(log.calls == ["drop focus", "drop focus"])
    }

    @Test("in a text field, typing and ↑ stay the field's; ↓ leaves it for the first row, whatever was lit")
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
        #expect(log.calls == ["drop focus"]) // Return was the field's
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
