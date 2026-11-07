import AppKit
import Testing
@testable import AutoHushApp

/// The menu's panel: Escape, the keys it hands on, its height following
/// its content with its top edge kept, and where it opens.
@Suite("MenuPanel")
@MainActor
struct MenuPanelTests {
    /// A key press, as the panel gets it.
    static func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], characters: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    /// Records the keys handed on to it.
    final class KeyRecorder: NSResponder {
        var keys: [UInt16] = []

        override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
    }

    @Test("Escape closes it; a key nothing in it takes goes to its handler")
    func keys() {
        let panel = MenuPanel(content: NSView())
        var cancelled = 0
        var keys: [UInt16] = []
        panel.onCancel = { cancelled += 1 }
        panel.onKey = { keys.append($0.keyCode); return true }
        panel.cancelOperation(nil)
        #expect(cancelled == 1)
        panel.keyDown(with: Self.key(125))
        #expect(keys == [125])
    }

    @Test("a key nothing in it takes ends there, without macOS's beep (a letter, Delete); Escape, ⌘ and ⌃ keys stay AppKit's (K3-4)")
    func untakenKeysEndThere() {
        let panel = MenuPanel(content: NSView())
        let after = KeyRecorder()
        panel.nextResponder = after // what AppKit would hand the key on to, and beep at its end
        panel.onKey = { _ in false }
        var cancelled = 0
        panel.onCancel = { cancelled += 1 }
        panel.keyDown(with: Self.key(0, characters: "a"))
        panel.keyDown(with: Self.key(51)) // Delete
        panel.keyDown(with: Self.key(122)) // F1
        #expect(after.keys.isEmpty)
        // Escape is left to AppKit, which calls `cancelOperation` itself on
        // macOS 14 and 15 and hands it on on macOS 27: either way it isn't
        // swallowed (the old-macOS round, 2026-11-07).
        panel.keyDown(with: Self.key(53, characters: "\u{1B}"))
        #expect(cancelled + after.keys.count == 1)
        after.keys.removeAll()
        panel.keyDown(with: Self.key(12, flags: .command, characters: "q"))
        panel.keyDown(with: Self.key(0, flags: .control, characters: "a"))
        #expect(after.keys == [12, 0])
    }

    @Test("its key view loop is worked out again as its content changes, so Tab reaches every control it shows")
    func recalculatesKeyViewLoop() {
        #expect(MenuPanel(content: NSView()).autorecalculatesKeyViewLoop)
    }

    @Test("it takes the keyboard unless told not to (the side window, but for VoiceOver or its search)")
    func takesKey() {
        let panel = MenuPanel(content: NSView())
        #expect(panel.canBecomeKey && !panel.canBecomeMain)
        panel.takesKey = false
        #expect(!panel.canBecomeKey)
    }

    @Test("its height follows its content, its top edge where it was; less than half a point changes nothing")
    func height() {
        let panel = MenuPanel(content: NSView())
        panel.setFrame(NSRect(x: 100, y: 300, width: 345, height: 400), display: false)
        panel.setContentHeight(250.2, animated: false)
        #expect(panel.frame == NSRect(x: 100, y: 450, width: 345, height: 250))
        panel.setContentHeight(250.4, animated: false)
        #expect(panel.frame.height == 250)
        panel.setContentHeight(500, animated: false)
        #expect(panel.frame == NSRect(x: 100, y: 200, width: 345, height: 500))
    }

    @Test("it opens 4 pt under its menu bar item, its left edge at the item's but kept on the screen, never past the screen's bottom")
    func placement() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let item = NSRect(x: 1000, y: 877, width: 30, height: 24)
        #expect(StatusMenuController.panelFrame(under: item, in: visible, width: 345, contentHeight: 700)
                == NSRect(x: 1000, y: 173, width: 345, height: 700))
        // Near the right edge: moved in, 6 pt from it.
        let right = NSRect(x: 1300, y: 877, width: 30, height: 24)
        #expect(StatusMenuController.panelFrame(under: right, in: visible, width: 345, contentHeight: 700).minX == 1089)
        // On a screen left of the main one, at its left edge: 6 pt in.
        let left = NSRect(x: -1440, y: 877, width: 30, height: 24)
        let otherScreen = NSRect(x: -1440, y: 0, width: 1440, height: 875)
        #expect(StatusMenuController.panelFrame(under: left, in: otherScreen, width: 345, contentHeight: 700).minX == -1434)
        // Taller than the screen: it ends 6 pt above the bottom, and scrolls.
        #expect(StatusMenuController.panelFrame(under: item, in: visible, width: 345, contentHeight: 2000)
                == NSRect(x: 1000, y: 6, width: 345, height: 867))
        #expect(StatusMenuController.fittingHeight(900, top: 873, in: visible) == 867)
        #expect(StatusMenuController.fittingHeight(500, top: 873, in: visible) == 500)
    }

    @Test("a side window opens left of the menu, level with its row, unless there's no room there; it stays on the screen")
    func sideWindowPlacement() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let menu = NSRect(x: 1000, y: 173, width: 345, height: 700)
        #expect(StatusMenuController.sideFrame(rowTop: 760, menu: menu, in: visible, width: 300, contentHeight: 400)
                == NSRect(x: 694, y: 368, width: 300, height: 400))
        // No room on the left: on the right.
        let leftMenu = NSRect(x: 200, y: 173, width: 345, height: 700)
        #expect(StatusMenuController.sideFrame(rowTop: 760, menu: leftMenu, in: visible, width: 300, contentHeight: 400).minX == 551)
        // Taller than the screen: the screen's height, from 6 pt under its top.
        #expect(StatusMenuController.sideFrame(rowTop: 760, menu: menu, in: visible, width: 300, contentHeight: 2000)
                == NSRect(x: 694, y: 6, width: 300, height: 863))
        // A row low on the screen: moved up so it ends 6 pt above the bottom.
        #expect(StatusMenuController.sideFrame(rowTop: 100, menu: menu, in: visible, width: 300, contentHeight: 400).minY == 6)
    }

    @Test("a pointer crossing other parts on its way to the side window keeps it open; one resting, moving away, or past its corners, doesn't", arguments: [
        (CGPoint(x: 900, y: 750), CGPoint(x: 800, y: 700), true), // toward it
        (CGPoint(x: 900, y: 750), CGPoint(x: 950, y: 700), false), // away
        (CGPoint(x: 900, y: 750), CGPoint(x: 800, y: 300), false), // below its bottom corner
        (CGPoint(x: 900, y: 750), CGPoint(x: 800, y: 870), false), // above its top corner
        (CGPoint(x: 900, y: 750), CGPoint(x: 900, y: 750), false), // resting
    ])
    func headingToTheSideWindow(from: CGPoint, to: CGPoint, heading: Bool) {
        let menu = NSRect(x: 700, y: 100, width: 345, height: 800)
        let side = NSRect(x: 394, y: 500, width: 300, height: 300) // left of the menu
        #expect(StatusMenuController.isHeading(from: from, to: to, toward: side, beside: menu) == heading)
    }

    @Test("the same for a side window on the menu's right, where there's no room on its left")
    func headingRight() {
        let menu = NSRect(x: 700, y: 100, width: 345, height: 800)
        let right = NSRect(x: 1051, y: 500, width: 300, height: 300)
        #expect(StatusMenuController.isHeading(from: CGPoint(x: 850, y: 750), to: CGPoint(x: 950, y: 720), toward: right, beside: menu))
        #expect(!StatusMenuController.isHeading(from: CGPoint(x: 850, y: 750), to: CGPoint(x: 800, y: 720), toward: right, beside: menu))
    }
}
