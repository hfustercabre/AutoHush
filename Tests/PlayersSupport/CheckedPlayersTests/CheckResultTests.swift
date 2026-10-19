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

    @Test("an app's traits come from its bundle: Electron's needs its launch option; CEF is Chromium; Flutter; a browser's web app names its browser; a dictionary means scripting")
    func traits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CheckResultTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
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
    }
}
