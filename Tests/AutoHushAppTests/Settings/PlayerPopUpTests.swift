import AppKit
import Testing
@testable import AutoHushApp
import AutoHushKit

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
        #expect(button.itemTitles == ["First", "Second", "Third", "", "Add a Web App…"])
        let players = Array(button.itemArray.prefix(3))
        #expect(players.map(\.isEnabled) == [true, true, false])
        #expect(players.map(\.subtitle) == [nil, nil, "Not installed"])
        #expect(players.allSatisfy { $0.image != nil })
        #expect(button.titleOfSelectedItem == "Second")
    }

    @Test("while none is chosen, a placeholder that can't be picked is shown")
    func placeholder() {
        let button = PlayerPopUpButton()
        button.update(options: options, selection: nil)
        #expect(button.itemTitles == ["Choose…", "First", "Second", "Third", "", "Add a Web App…"])
        #expect(button.itemArray.first?.isEnabled == false)
        #expect(button.titleOfSelectedItem == "Choose…")

        // Chosen since: the placeholder goes.
        button.update(options: options, selection: "com.example.first")
        #expect(button.itemTitles == ["First", "Second", "Third", "", "Add a Web App…"])
    }

    @Test("“Add a Web App…” opens the window, and the chosen player stays shown")
    func addWebApp() {
        let button = PlayerPopUpButton()
        var picked: [String] = []
        var adds = 0
        button.onSelect = { picked.append($0) }
        button.onAddWebApp = { adds += 1 }
        button.update(options: options, selection: "com.example.second")
        button.selectItem(withTitle: "Add a Web App…")
        _ = button.target?.perform(button.action, with: button)
        #expect(adds == 1)
        #expect(picked.isEmpty)
        #expect(button.titleOfSelectedItem == "Second")
    }

    @Test("a suggested web app can be picked though not installed; the chosen player stays shown")
    func suggestion() {
        let button = PlayerPopUpButton()
        var picked: [String] = []
        button.onSelect = { picked.append($0) }
        let suggestion = PlayerOption.suggestion(WebAppSuggestion(name: "Deezer", address: "deezer.com"))
        button.update(options: options + [suggestion], selection: "com.example.second")
        let heading = button.itemArray.first { $0.identifier?.rawValue == "webAppsHeading" }
        #expect(heading?.title == "Safari Web Apps")
        #expect(heading?.isEnabled == false)
        #expect(heading?.view != nil)
        #expect(button.itemTitles.firstIndex(of: "Safari Web Apps") == button.itemTitles.firstIndex(of: "Deezer").map { $0 - 1 })
        let item = button.itemArray.first { $0.title == "Deezer" }
        #expect(item?.isEnabled == true)
        #expect(item?.subtitle == "Not installed")
        #expect(item?.image?.isTemplate == true)

        button.selectItem(withTitle: "Deezer")
        _ = button.target?.perform(button.action, with: button)
        #expect(picked == [suggestion.bundleID])
        #expect(button.titleOfSelectedItem == "Second")
    }

    @Test("an untested web app's item shows the “Untested” badge after its name")
    func untested() {
        let button = PlayerPopUpButton()
        var untested = PlayerOption(bundleID: "com.apple.Safari.WebApp.U", name: "SoundCloud",
                                    appURL: URL(fileURLWithPath: "/Applications/SoundCloud.app"), kind: .safariWebApp)
        untested.isUntested = true
        button.update(options: options + [untested], selection: "com.example.first")
        let item = button.itemArray.first { $0.title == "SoundCloud" }
        #expect(item?.isEnabled == true)
        #expect(item?.attributedTitle?.containsAttachments(in: NSRange(location: 0, length: item?.attributedTitle?.length ?? 0)) == true)
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

    @Test("updating with the same players and choice keeps the menu as it is")
    func noNeedlessRebuild() {
        let button = PlayerPopUpButton()
        button.update(options: options, selection: "com.example.first")
        let items = button.itemArray
        button.update(options: options, selection: "com.example.first")
        #expect(zip(items, button.itemArray).allSatisfy { $0 === $1 })

        button.update(options: options, selection: "com.example.second")
        #expect(button.titleOfSelectedItem == "Second")
    }

    @Test("a pick that isn't taken goes back to the chosen player")
    func pickNotTaken() {
        let button = PlayerPopUpButton()
        button.update(options: options, selection: "com.example.first")
        button.selectItem(at: 1) // the user picks Second, but the choice stays First
        button.update(options: options, selection: "com.example.first")
        #expect(button.titleOfSelectedItem == "First")
    }
}
