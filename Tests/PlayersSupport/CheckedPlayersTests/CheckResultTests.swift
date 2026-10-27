import Foundation
import Testing
@testable import CheckedPlayers
import WebAppPlayers
import AutoHushTestSupport
import PlayersTestSupport

@Suite("CheckResult")
struct CheckResultTests {
    private let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause",
                                         places: [ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)])
    private let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"),
                                    ways: [.page(PageAccess(interface: .electron, switchAttribute: PageAccess.electronSwitch))],
                                    needsLaunchOption: true)

    @Test("what a check found reads back as playercheck wrote it")
    func codable() throws {
        let result = CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .some, failedStates: [.minimized, .hidden]),
                                        CheckResult.WayResult(kind: .script, mark: .notThere)],
                                 setup: setup, pageButton: recipe)
        #expect(try JSONDecoder().decode(CheckResult.self, from: JSONEncoder().encode(result)) == result)
        #expect(result.ways.first { $0.kind == .page }?.worked == true)
        #expect(result.ways.first { $0.kind == .script }?.worked == false)
    }

    @Test("a check saved before windows closed reads back as it was; windows closed is saved by its own name")
    func savedBeforeWindowsClosed() throws {
        let saved = Data(#"{"ways":[{"kind":"page","mark":"some","failedStates":["otherDesktopCovered","hidden"]},"#.utf8)
            + Data(#"{"kind":"panel","mark":"works","failedStates":[]}]}"#.utf8)
        let read = try JSONDecoder().decode(CheckResult.self, from: saved)
        #expect(read.ways == [CheckResult.WayResult(kind: .page, mark: .some, failedStates: [.otherDesktopCovered, .hidden]),
                              CheckResult.WayResult(kind: .panel, mark: .works)])
        #expect(read.setup == nil && read.pageButton == nil && !read.windowsClosed)
        let found = CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .noWindow)], setup: nil, windowsClosed: true)
        #expect(try JSONDecoder().decode(CheckResult.self, from: JSONEncoder().encode(found)) == found)
        let closed = CheckResult.WayResult(kind: .panel, mark: .some, failedStates: [.windowsClosed])
        #expect(String(decoding: try JSONEncoder().encode(closed), as: UTF8.self).contains(#""windowsClosed""#))
        #expect(try JSONDecoder().decode(CheckResult.WayResult.self, from: JSONEncoder().encode(closed)) == closed)
    }

    @Test("a check moves a window through its 7 states, in their order; windows closed isn't one, and each has a title of its own")
    func windowTrip() {
        #expect(CheckResult.WindowState.trip == [.visible, .covered, .otherDesktop, .otherDesktopCovered, .fullScreen, .minimized, .hidden])
        #expect(CheckResult.WindowState.windowsClosed.title == "windows closed")
        #expect(Set(CheckResult.WindowState.allCases.map(\.title)).count == CheckResult.WindowState.allCases.count)
    }

    @Test("keeping it keeps the setup, and its page's button as a web app's; nothing when no way worked")
    func keeping() {
        let store = MemorySetupStore()
        let recipes = MemoryRecipeStore()
        let players = CheckedPlayers(store: store)
        players.keep(CheckResult(ways: [], setup: nil, pageButton: recipe), recipes: recipes)
        #expect(store.setups().isEmpty && recipes.recipe(for: setup.bundleID) == nil)
        players.keep(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .works)], setup: setup, pageButton: recipe), recipes: recipes)
        #expect(store.setups() == [setup])
        #expect(recipes.recipe(for: setup.bundleID) == recipe)
    }

    @Test("an app checked again gets a new player, even with the same setup: the one made before doesn't know the button the new check learned")
    func checkedAgain() {
        let store = MemorySetupStore()
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        players.keep(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .works)], setup: setup), recipes: MemoryRecipeStore())
        let first = players.current()
        #expect(players.current().first === first.first) // kept while nothing changes
        players.keep(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .works)], setup: setup, pageButton: recipe), recipes: MemoryRecipeStore())
        #expect(players.current().map(\.bundleID) == [setup.bundleID])
        #expect(players.current().first !== first.first)
    }

    @Test("removing an added app forgets its setup and its page's button; it's no longer offered")
    func forgetting() {
        let store = MemorySetupStore()
        let recipes = MemoryRecipeStore()
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        players.keep(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .works)], setup: setup, pageButton: recipe), recipes: recipes)
        #expect(players.current().map(\.bundleID) == [setup.bundleID])
        players.forget(setup.bundleID, recipes: recipes)
        #expect(store.setups().isEmpty && recipes.recipe(for: setup.bundleID) == nil)
        #expect(players.current().isEmpty)
    }

    @Test("an app's traits come from its bundle: its framework (Electron's with its launch option), a web app's browser, a dictionary")
    func traits() throws {
        let scratch = TemporaryFolder("CheckResultTests", create: false)
        let folder = scratch.url
        func app(_ name: String, framework: String) throws -> URL {
            try TestAppBundle.make(in: folder, name: name, frameworks: [framework])
        }
        let electron = try app("Electron", framework: "Electron Framework")
        let cef = try app("Embedded", framework: "Chromium Embedded Framework"), flutter = try app("Flutter", framework: "FlutterMacOS")
        let scripted = try TestAppBundle.make(in: folder, name: "Scripted", resources: ["Scripted.sdef": ""])
        let chromeApp = try TestAppBundle.make(in: folder, name: "SoundCloud", info: [
            "CFBundleIdentifier": "com.google.Chrome.app.test", "CrAppModeShortcutURL": "https://soundcloud.com/",
            "CrBundleIdentifier": "com.google.Chrome",
        ])

        #expect(CheckedAppTraits.browser(ofAppAt: chromeApp) == "com.google.Chrome")
        #expect(CheckedAppTraits.browser(ofAppAt: electron) == nil)
        #expect(CheckedAppTraits.of(appAt: electron) == CheckedAppTraits(scriptable: false, framework: .electron, needsLaunchOption: true))
        #expect(CheckedAppTraits.of(appAt: cef) == CheckedAppTraits(scriptable: false, framework: .chromium, needsLaunchOption: false))
        #expect(CheckedAppTraits.of(appAt: flutter) == CheckedAppTraits(scriptable: false, framework: .flutter, needsLaunchOption: false))
        #expect(CheckedAppTraits.of(appAt: chromeApp)
            == CheckedAppTraits(scriptable: false, framework: .browserWebApp(browserID: "com.google.Chrome"), needsLaunchOption: false))
        #expect(CheckedAppTraits.of(appAt: scripted) == CheckedAppTraits(scriptable: true, framework: nil, needsLaunchOption: false))
        withExtendedLifetime(scratch) {}
    }
}
