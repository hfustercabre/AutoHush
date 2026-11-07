import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// A card's Restore Defaults, pressed by the keys, by VoiceOver, or by a
/// click (T-1, T-8, the full check, 2026-11-06).
@Suite("RestoreDefaultsButton", .application, .waitsTimeLimit)
@MainActor
struct RestoreDefaultsButtonTests {
    private let actions = FakeAppActions()

    /// A card with a switch and its Restore Defaults, in a window, its
    /// timing changed so the button shows; its highlight moved by the keys
    /// alone (T-5).
    private func shown() async -> (model: SettingsModel, keys: KeyHighlight, window: NSWindow) {
        let model = SettingsModel.forTests(actions: actions)
        var timings = model.timings
        timings.startConfirmation = 2
        model.setTimings(timings)
        let keys = KeyHighlight()
        keys.followsPointer = false
        let card = Card(Text(verbatim: "Pausing")) {
            SwitchRow(Text(verbatim: "A switch"), isOn: .constant(true))
        } footer: {
            RestoreDefaultsButton(model: model, card: .timing)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: card.padding().environment(keys).environment(\.voiceOver, VoiceOverSetting { false }))
        window.orderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        await TestWait.until { keys.rows.count == 2 } // the switch, then the button
        return (model, keys, window)
    }

    @Test("pressed by the keys, it restores the card and leaves the highlight on its first row (U2)")
    func keysPress() async throws {
        let (model, keys, window) = await shown()
        defer { window.close() }
        let first = try #require(keys.rows.first?.first)
        keys.jump(.last)
        #expect(keys.highlighted != first)
        #expect(keys.press())
        #expect(model.isDefault(.timing))
        await TestWait.until { keys.highlighted == first }
        #expect(keys.highlighted == first && keys.isLitByKeys)
    }

    @Test("a press by the keys, or with VoiceOver on, moves the highlight; a click's doesn't (N8)")
    func whoseHighlightMoves() {
        let on = VoiceOverSetting { true }, off = VoiceOverSetting { false }
        let keys = KeyHighlight()
        #expect(!RestoreDefaultsButton.movesHighlight(keyboard: keys, voiceOver: off)) // a click
        #expect(!RestoreDefaultsButton.movesHighlight(keyboard: nil, voiceOver: off))
        #expect(RestoreDefaultsButton.movesHighlight(keyboard: keys, voiceOver: on)) // VoiceOver's press
        var byKeys: Bool?
        let button = UUID()
        keys.register(button, .init(frame: CGRect(x: 0, y: 0, width: 100, height: 20), press: {
            byKeys = RestoreDefaultsButton.movesHighlight(keyboard: keys, voiceOver: off)
        }))
        keys.move(1)
        #expect(keys.press())
        #expect(byKeys == true)
    }
}
