import AppKit
import Testing
@testable import AutoHushApp

@Suite("PlayerPopUp")
@MainActor
struct PlayerPopUpTests {
    private let options = [
        PlayerOption(bundleID: "com.example.first", name: "First", appURL: URL(fileURLWithPath: "/Applications/First.app")),
        PlayerOption(bundleID: "com.example.second", name: "Second", appURL: URL(fileURLWithPath: "/Applications/Second.app")),
        PlayerOption(bundleID: "com.example.third", name: "Third", appURL: nil),
    ]

    @Test("each player is an item with its icon; one that isn't installed is dimmed and says so")
    func items() {
        let button = PlayerPopUpButton()
        button.update(options: options, selection: "com.example.second")
        #expect(button.itemTitles == ["First", "Second", "Third"])
        #expect(button.itemArray.map(\.isEnabled) == [true, true, false])
        #expect(button.itemArray.map(\.subtitle) == [nil, nil, "Not installed"])
        #expect(button.itemArray.allSatisfy { $0.image != nil })
        #expect(button.titleOfSelectedItem == "Second")
    }

    @Test("while none is chosen, a placeholder that can't be picked is shown")
    func placeholder() {
        let button = PlayerPopUpButton()
        button.update(options: options, selection: nil)
        #expect(button.itemTitles == ["Choose…", "First", "Second", "Third"])
        #expect(button.itemArray.first?.isEnabled == false)
        #expect(button.titleOfSelectedItem == "Choose…")

        // Chosen since: the placeholder goes.
        button.update(options: options, selection: "com.example.first")
        #expect(button.itemTitles == ["First", "Second", "Third"])
    }

    @Test("picking a player reports its bundle ID")
    func pick() {
        let button = PlayerPopUpButton()
        var picked: [String] = []
        button.onSelect = { picked.append($0) }
        button.update(options: options, selection: "com.example.first")

        button.selectItem(at: 1)
        button.sendAction(button.action, to: button.target)
        #expect(picked == ["com.example.second"])
    }
}
