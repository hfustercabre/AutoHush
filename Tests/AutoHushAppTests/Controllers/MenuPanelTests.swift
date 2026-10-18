import AppKit
import Testing
@testable import AutoHushApp

/// The menu's panel: Escape, the keys it hands on, its height following
/// its content with its top edge kept, and where it opens.
@Suite("MenuPanel")
@MainActor
struct MenuPanelTests {
    /// A key press, as the panel gets it.
    static func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
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
}
