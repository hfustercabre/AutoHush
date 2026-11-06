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
        CheckWarningWindowController(app: World().apps[0], muting: .none, desktopShortcutsOff: { false }) {
            log.calls.append("start")
        }
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
        let sut = PlayerChooserWindowController(model: model, tallestPage: 600)
        defer { sut.close() }
        sut.show()
        let window = try #require(sut.window)
        let keys = try #require(sut.keys)
        await TestWait.until { keys.highlight.rows.count > 1 }
        window.makeFirstResponder(nil)
        #expect(try key(sut, 36, "\r")) // Continue dimmed: nothing, no beep
        #expect(try key(sut, 125)) // ↓: the first tile
        #expect(try key(sut, 49, " ")) // picked
        await TestWait.until { (try? key(sut, 36, "\r")) == false } // Continue's, once it's on
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
        let sut = AddWebAppWindowController(model: AddWebAppModel(), settings: settings)
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
}
