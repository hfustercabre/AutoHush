import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp

/// A pop-up opened from the keys finds the AppKit pop-up button SwiftUI
/// draws for it.
@Suite("PopUpOpener")
@MainActor
struct PopUpOpenerTests {
    @Test("behind a menu-style picker, it finds the pop-up button AppKit draws there")
    func findsPopUpButton() {
        let opener = PopUpOpener()
        let picker = Picker("Choice", selection: .constant(1)) {
            Text(verbatim: "One").tag(1)
            Text(verbatim: "Two").tag(2)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .buttonStyle(.borderless)
        .fixedSize()
        .opened(by: opener)
        .padding(20)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: picker)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // SwiftUI fills its items in as it opens: the button is what counts.
        #expect(opener.popUpButton != nil)
    }

    @Test("with nothing behind it, it opens nothing")
    func nothingToOpen() {
        let opener = PopUpOpener()
        #expect(opener.popUpButton == nil)
        opener.open()
    }
}
