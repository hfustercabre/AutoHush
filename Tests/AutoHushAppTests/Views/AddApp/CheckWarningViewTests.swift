import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The window before a check, drawn as it shows. `NSApp` gives it its icon.
@Suite("The warning before a check, drawn", .application)
@MainActor
struct CheckWarningViewTests {
    @Test("with the desktop shortcuts off, it draws their note and Open Keyboard Settings… under the window states")
    func desktopShortcutsOff() {
        let app = World().apps[0]
        func height(keysOff: Bool) -> CGFloat {
            drawn(CheckWarningView(app: app, desktopShortcutsOff: keysOff, start: {}, cancel: {}),
                  width: CheckWarningView.width, height: 1400).height
        }
        #expect(height(keysOff: true) > height(keysOff: false) + 40) // a note's lines and a button
    }

    @Test("with the app's windows all closed, it draws their one state and no moving or blocked input: shorter (W2 of 1.2.2)")
    func windowsClosed() {
        let app = World().apps[0]
        func height(closed: Bool) -> CGFloat {
            drawn(CheckWarningView(app: app, windowsClosed: closed, start: {}, cancel: {}),
                  width: CheckWarningView.width, height: 1400).height
        }
        #expect(height(closed: true) < height(closed: false) - 150) // one state, no "While It Moves Them"
    }
}
