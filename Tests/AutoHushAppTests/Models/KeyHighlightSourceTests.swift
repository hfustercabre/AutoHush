import CoreGraphics
import Foundation
import Testing
@testable import AutoHushApp

/// What lit the highlight (the keys outline it, A2a), the keyboard's focus
/// hidden while something is highlighted (K9), and dimmed controls that
/// explain themselves to the keys (A13a).
@Suite("KeyHighlight's source")
@MainActor
struct KeyHighlightSourceTests {
    private func control(_ keyboard: KeyHighlight, _ y: CGFloat, enabled: Bool = true, explains: Bool = false,
                         pressed: (() -> Void)? = nil) -> UUID {
        let id = UUID()
        keyboard.register(id, .init(frame: CGRect(x: 0, y: y, width: 44, height: 22), isEnabled: enabled,
                                    explains: explains, press: pressed))
        return id
    }

    @Test("a light knows whether the keys or the pointer put it there, whichever moved it last")
    func byKeys() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0)
        let second = control(keyboard, 50)
        keyboard.move(1)
        #expect(keyboard.light(first).byKeys)
        keyboard.hover(second, true)
        #expect(keyboard.highlighted == second && !keyboard.light(second).byKeys)
        keyboard.move(-1)
        #expect(keyboard.highlighted == first && keyboard.light(first).byKeys)
        keyboard.hover(first, true) // the pointer onto the control the keys are on
        #expect(!keyboard.light(first).byKeys)
    }

    @Test("the keyboard's focus hides while something is highlighted, here or in the partner, and shows again once nothing is")
    func hidesFocus() {
        let sidebar = KeyHighlight(), page = KeyHighlight()
        sidebar.partner = page
        page.partner = sidebar
        let row = control(sidebar, 0)
        let button = control(page, 0)
        #expect(!sidebar.hidesFocus && !page.hidesFocus)
        page.hover(button, true)
        #expect(page.hidesFocus && sidebar.hidesFocus)
        page.hover(button, false)
        #expect(!page.hidesFocus && !sidebar.hidesFocus)
        sidebar.move(1)
        #expect(sidebar.highlighted == row && page.hidesFocus)
        sidebar.clear() // nothing lit: the focus shows again
        #expect(!page.hidesFocus && !sidebar.hidesFocus)
    }

    @Test("a dimmed control that explains itself takes the keys' highlight, shows it only to the keys, keeps it as it dims, and isn't pressed")
    func explains() {
        let keyboard = KeyHighlight()
        var presses = 0
        let first = control(keyboard, 0)
        let dimmed = control(keyboard, 50, enabled: false, explains: true, pressed: { presses += 1 })
        _ = control(keyboard, 100, enabled: false) // dimmed, nothing to say: skipped
        keyboard.move(1)
        keyboard.move(1)
        #expect(keyboard.highlighted == dimmed)
        #expect(keyboard.shows(dimmed, isEnabled: false))
        #expect(!keyboard.press())
        #expect(presses == 0)
        keyboard.move(1) // past the one that says nothing, round to the first
        #expect(keyboard.highlighted == first)
        keyboard.hover(dimmed, true) // the pointer has its help tag instead
        #expect(!keyboard.shows(dimmed, isEnabled: false))

        let enabled = control(keyboard, 150, explains: true)
        keyboard.move(1) // from the dimmed one, on down
        #expect(keyboard.highlighted == enabled)
        keyboard.update(enabled, isEnabled: false) // dimmed under the keys: it says why
        #expect(keyboard.highlighted == enabled)
    }

    @Test("a reason that comes or goes after a control registered changes whether the keys stop on it, and a dimmed one losing its reason under the keys loses the highlight (K3-3)")
    func reasonChanges() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0)
        let dimmed = control(keyboard, 50, enabled: false) // registered with no reason yet
        #expect(keyboard.rows == [[first]])
        keyboard.update(dimmed, explains: true) // its reason came (Option let go in the players)
        #expect(keyboard.rows == [[first], [dimmed]])
        keyboard.move(1)
        keyboard.move(1)
        #expect(keyboard.highlighted == dimmed && keyboard.shows(dimmed, isEnabled: false))
        keyboard.update(dimmed, explains: false) // gone again: nothing to say, nothing to stop on
        #expect(keyboard.rows == [[first]])
        #expect(keyboard.highlighted == nil)
    }
}
