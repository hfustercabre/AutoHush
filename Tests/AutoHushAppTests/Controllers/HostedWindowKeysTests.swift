import AppKit
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The guiding windows' keys as their window takes them (`WindowKeys`,
/// A4c): Return left to the main button whatever is lit (R2), taken while
/// it's dimmed, Space for the lit control, and in the welcome window a
/// letter typed into the search (T1). (SwiftUI presses a default button
/// only in a key window, which a test's never is.)
@Suite("Guiding windows' keys", .application, .waitsTimeLimit)
@MainActor
struct HostedWindowKeysTests {
    private func key(_ sut: HostedWindowController, _ keyCode: UInt16, _ characters: String? = nil) throws -> Bool {
        let window = try #require(sut.window)
        return sut.handleKey(keyCode, flags: [], characters: characters, windowNumber: window.windowNumber)
    }

    private func makeWarning(log: CallLog) -> CheckWarningWindowController {
        keysAlone(CheckWarningWindowController(app: World().apps[0], muting: .none, desktopShortcutsOff: { false }) {
            log.calls.append("start")
        })
    }

    /// `sut` with its highlight moved by the keys alone, keyboard navigation
    /// off, whatever the test Mac's: the pointer, resting wherever its window
    /// opens, never moves it (T-1, T-5).
    private func keysAlone<Controller: HostedWindowController>(_ sut: Controller) -> Controller {
        sut.keys?.highlight.followsPointer = false
        sut.fullKeyboardAccess = { false }
        return sut
    }

    @Test("with Cancel lit, Return is left to the window for Start the Check; another window's keys, or ⌘ with one, aren't taken")
    func returnIsTheMainButtons() async throws {
        let log = CallLog()
        let sut = makeWarning(log: log)
        defer { sut.close() }
        sut.show()
        let window = try #require(sut.window)
        let keys = try #require(sut.keys)
        await TestWait.until { keys.highlight.rows.joined().count == 2 } // Cancel and Start the Check
        #expect(!sut.handleKey(125, flags: [], characters: nil, windowNumber: window.windowNumber + 1))
        #expect(!sut.handleKey(125, flags: .command, characters: nil, windowNumber: window.windowNumber))
        #expect(try key(sut, 125)) // ↓: Cancel, first in its row
        #expect(keys.highlight.highlighted == keys.highlight.rows.first?.first)
        #expect(try !key(sut, 36, "\r")) // SwiftUI gives it to Start the Check
        #expect(log.calls.isEmpty && sut.isOpen) // not to Cancel
    }

    @Test("Space presses the lit control: Cancel closes the warning, the check not started")
    func spacePressesTheLit() async throws {
        let log = CallLog()
        let sut = makeWarning(log: log)
        defer { sut.close() }
        sut.show()
        let keys = try #require(sut.keys)
        await TestWait.until { keys.highlight.rows.joined().count == 2 }
        #expect(try key(sut, 125))
        #expect(try key(sut, 49, " "))
        await TestWait.until { !sut.isOpen }
        #expect(log.calls.isEmpty)
    }

    @Test("in the welcome window, Return does nothing while Continue is dimmed and is left to it once a tile is picked; a letter typed goes to the search (T1)")
    func welcome() async throws {
        let log = CallLog()
        let model = SettingsModel.forTests(actions: FakeAppActions(log: log), updates: FakeUpdateCommands())
        model.state.status.playerOptions = (0..<PlayerOption.searchThreshold).map {
            PlayerOption(bundleID: "com.example.player\($0)", name: "Player \($0)", appURL: URL(fileURLWithPath: "/Applications/P\($0).app"))
        }
        let sut = keysAlone(PlayerChooserWindowController(model: model, tallestPage: 600))
        defer { sut.close() }
        sut.show()
        let window = try #require(sut.window)
        let keys = try #require(sut.keys)
        await TestWait.until { keys.highlight.rows.count > 1 }
        window.makeFirstResponder(nil)
        #expect(try key(sut, 36, "\r")) // Continue dimmed: nothing, no beep
        #expect(try key(sut, 125)) // ↓: the first tile
        #expect(try key(sut, 49, " ")) // picked
        // Continue on, then Return once (the 2026-11-06 full check's T-16:
        // not a Return each poll).
        await TestWait.until { keys.mainButtonEnabled }
        #expect(try !key(sut, 36, "\r")) // Continue's
        #expect(log.calls.isEmpty) // the window's Return, not the keys', presses it

        // T1: lit, a letter goes on to the search, which takes the keyboard.
        #expect(keys.highlight.highlighted != nil)
        #expect(try !key(sut, 0, "a"))
        #expect(window.firstResponder is NSText)
        #expect(keys.highlight.highlighted == nil)
        #expect(try !key(sut, 126)) // ↑ from the search: the field's
        #expect(try key(sut, 125)) // ↓ from it: the tiles again
        #expect(keys.highlight.highlighted != nil && !(window.firstResponder is NSText))
    }

    @Test("in Add a Web App, a letter typed with a control lit goes back into the address, the highlight let go; Shift-Tab there stays in it (N5)")
    func addWebAppAddress() async throws {
        let settings = SettingsModel.forTests(actions: FakeAppActions(log: CallLog()), updates: FakeUpdateCommands())
        let sut = keysAlone(AddWebAppWindowController(model: AddWebAppModel(), settings: settings))
        defer { sut.close() }
        sut.show()
        let window = try #require(sut.window)
        let keys = try #require(sut.keys)
        await TestWait.until { !keys.highlight.rows.isEmpty }
        window.makeFirstResponder(nil)
        #expect(try key(sut, 125)) // ↓: a control lit
        #expect(keys.highlight.highlighted != nil)
        #expect(try !key(sut, 0, "a")) // the letter goes on, into the address
        #expect(window.firstResponder is NSText)
        #expect(keys.highlight.highlighted == nil)
        #expect(sut.handleKey(48, flags: .shift, characters: nil, windowNumber: window.windowNumber)) // Shift-Tab: nothing
        #expect(window.firstResponder is NSText && keys.highlight.highlighted == nil)
    }

    @Test("while an input method composes in a field, its keys are left to it: in the welcome window and Add a Web App")
    func inputMethodComposing() throws {
        let settings = SettingsModel.forTests(actions: FakeAppActions(log: CallLog()), updates: FakeUpdateCommands())
        let windows: [HostedWindowController] = [
            keysAlone(PlayerChooserWindowController(model: settings, tallestPage: 600)),
            keysAlone(AddWebAppWindowController(model: AddWebAppModel(), settings: settings)),
        ]
        // Not shown: a window of the test's made key meanwhile took the menu
        // tests' key from their side window.
        for sut in windows {
            let window = try #require(sut.window)
            let keys = try #require(sut.keys)
            let editor = ComposingEditor(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
            window.contentView?.addSubview(editor)
            defer { editor.removeFromSuperview() }
            #expect(window.makeFirstResponder(editor))
            for code: UInt16 in [125, 126, 48, 53, 36] { // ↓, ↑, Tab, Escape, Return
                #expect(try !key(sut, code), "\(type(of: sut)), key \(code)")
            }
            #expect(!sut.handleKey(48, flags: .shift, characters: nil, windowNumber: window.windowNumber))
            #expect(keys.highlight.highlighted == nil && window.firstResponder === editor)
            editor.composing = false
            #expect(try key(sut, 125), "\(type(of: sut)): ↓ from the field once it's done") // the keys' again
        }
    }
}

/// A field's editor while an input method composes in it (marked text), as
/// `hasMarkedText` tells, with no input method or field needed.
private final class ComposingEditor: NSTextView {
    var composing = true
    override func hasMarkedText() -> Bool { composing }
}
