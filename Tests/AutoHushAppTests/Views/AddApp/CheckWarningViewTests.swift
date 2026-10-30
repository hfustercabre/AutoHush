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
}
