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

    @Test("the pointer on a dimmed control that doesn't explain itself leaves the highlight off it, unseen: on the one around it, or nothing, so the focus's tint and keys stay (app-models-2)")
    func pointerOnDimmed() {
        let keyboard = KeyHighlight()
        let card = UUID(), dimmed = UUID()
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 0, width: 300, height: 100)))
        keyboard.register(dimmed, .init(frame: CGRect(x: 10, y: 50, width: 80, height: 22), isEnabled: false))
        keyboard.hover(dimmed, true) // alone under the pointer
        #expect(keyboard.highlighted == nil && !keyboard.hidesFocus)
        keyboard.hover(card, true)
        #expect(keyboard.highlighted == card)
        keyboard.hover(dimmed, true) // inside the card, came onto last
        #expect(keyboard.highlighted == card)
        keyboard.hover(dimmed, false)
        #expect(keyboard.highlighted == card)
    }

    @Test("VoiceOver's cursor moved by its own keys brings the highlight, as the keys' but no arrival (its cursor is there already); not onto a dimmed control without a reason; Settings' other side lets go (K5)")
    func followsVoiceOver() {
        let sidebar = KeyHighlight(), page = KeyHighlight()
        var sides: [String] = []
        sidebar.onHighlight = { sides.append("sidebar"); page.clear() }
        page.onHighlight = { sides.append("page"); sidebar.clear() }
        let row = control(sidebar, 0)
        let button = control(page, 0)
        let dimmed = control(page, 50, enabled: false)
        let explaining = control(page, 100, enabled: false, explains: true)
        page.move(1)
        #expect(page.highlighted == button)
        sidebar.followVoiceOver(to: row)
        #expect(sidebar.highlighted == row && page.highlighted == nil)
        #expect(sidebar.light(row).byKeys && sidebar.light(row).arrivals == 0)
        page.followVoiceOver(to: dimmed) // nothing to show there
        #expect(page.highlighted == nil && sidebar.highlighted == row)
        page.followVoiceOver(to: explaining)
        #expect(page.highlighted == explaining && sidebar.highlighted == nil)
        page.followVoiceOver(to: explaining) // already there
        #expect(sides == ["page", "sidebar", "page"])
    }

    @Test("VoiceOver's cursor on screen finds the innermost control around its element that takes the highlight, in screen coordinates, a dimmed one that explains itself too; none for an element far larger than the control (a window), off the controls, or before they're placed on screen (K5)")
    func controlAroundElement() {
        let keyboard = KeyHighlight()
        let row = control(keyboard, 0)
        _ = control(keyboard, 50, enabled: false)
        let explaining = control(keyboard, 75, enabled: false, explains: true)
        let card = UUID()
        keyboard.register(card, .init(frame: CGRect(x: 0, y: 0, width: 200, height: 100)))
        let onRow = CGRect(x: 104, y: 204, width: 30, height: 14)
        #expect(keyboard.control(around: onRow) == nil) // not placed yet
        keyboard.screenFrame = { $0.offsetBy(dx: 100, dy: 200) }
        #expect(keyboard.control(around: onRow) == row) // inside the card too
        #expect(keyboard.control(around: CGRect(x: 104, y: 254, width: 30, height: 14)) == card) // the dimmed one's place
        #expect(keyboard.control(around: CGRect(x: 104, y: 279, width: 30, height: 14)) == explaining)
        #expect(keyboard.control(around: CGRect(x: 280, y: 280, width: 10, height: 10)) == card)
        #expect(keyboard.control(around: CGRect(x: 100, y: 200, width: 600, height: 400)) == nil) // a window
        #expect(keyboard.control(around: CGRect(x: 400, y: 210, width: 10, height: 10)) == nil)
    }

    @Test("without Accessibility, the keyboard's focus that VoiceOver moves brings the highlight, as the keys', but not the focus a key's own arrival brings a moment later, taken once; it goes out with the focus (unless a key acted on it since), and when VoiceOver moved and nothing put it there lately (D-1, W-1)")
    func followsFocus() {
        let keyboard = KeyHighlight()
        let first = control(keyboard, 0)
        let second = control(keyboard, 50)
        let third = control(keyboard, 100)
        keyboard.followFocus(to: third) // VoiceOver's keys moved the focus there
        #expect(keyboard.highlighted == third && keyboard.light(third).byKeys)
        keyboard.highlight(first)
        keyboard.highlight(second)
        keyboard.followFocus(to: first) // the first arrival's focus, late
        #expect(keyboard.highlighted == second)
        keyboard.followFocus(to: second) // the second's: on it already
        keyboard.followFocus(to: first) // VoiceOver went back there: its echo was taken
        #expect(keyboard.highlighted == first)
        keyboard.focusGone() // to no control: it goes out with the focus
        #expect(keyboard.highlighted == nil)

        keyboard.highlight(second)
        keyboard.followFocus(to: second) // the keys' own echo
        keyboard.focusGone() // isn't the focus's light
        #expect(keyboard.highlighted == second)
        keyboard.voiceOverMoved() // put there just now
        #expect(keyboard.highlighted == second)
        keyboard.voiceOverMoved(now: .now + .seconds(1)) // VoiceOver went on, onto what the focus can't reach
        #expect(keyboard.highlighted == nil)

        let pressable = control(keyboard, 150, pressed: {})
        keyboard.followFocus(to: pressable)
        #expect(keyboard.press()) // a key acted on it: the keys' now
        keyboard.focusGone() // the window let the focus go after the key
        #expect(keyboard.highlighted == pressable)

        let list = UUID() // the logs' entries: ↑ and ↓ scroll them
        keyboard.register(list, .init(frame: CGRect(x: 0, y: 200, width: 44, height: 22), scroll: { _ in true }))
        keyboard.followFocus(to: list)
        #expect(keyboard.scroll(1)) // scrolled by a key: the keys' now
        keyboard.focusGone()
        #expect(keyboard.highlighted == list)
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
