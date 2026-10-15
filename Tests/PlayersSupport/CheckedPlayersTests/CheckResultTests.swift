import Foundation
import Testing
@testable import CheckedPlayers
import WebAppPlayers

/// Recipes kept in memory.
private final class Recipes: PlayPauseRecipeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: PlayPauseRecipe] = [:]
    func recipe(for bundleID: String) -> PlayPauseRecipe? { lock.withLock { kept[bundleID] } }
    func save(_ recipe: PlayPauseRecipe, for bundleID: String) { lock.withLock { kept[bundleID] = recipe } }
    func forget(for bundleID: String) { lock.withLock { kept[bundleID] = nil } }
}

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
        #expect(result.way(.page)?.worked == true)
        #expect(result.way(.script)?.worked == false)
    }

    @Test("keeping it keeps the setup, and its page's button as a web app's; nothing when no way worked")
    func keeping() {
        let store = MemoryStore()
        let recipes = Recipes()
        let players = CheckedPlayers(store: store)
        players.keep(CheckResult(ways: [], setup: nil, pageButton: recipe), recipes: recipes)
        #expect(store.setups().isEmpty && recipes.recipe(for: setup.bundleID) == nil)
        players.keep(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .works)], setup: setup, pageButton: recipe), recipes: recipes)
        #expect(store.setups() == [setup])
        #expect(recipes.recipe(for: setup.bundleID) == recipe)
    }

    @Test("an app's traits come from its bundle: Electron's needs its launch option; a dictionary means scripting")
    func traits() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CheckResultTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let electron = folder.appendingPathComponent("Electron.app")
        try FileManager.default.createDirectory(at: electron.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
                                                withIntermediateDirectories: true)
        let scripted = folder.appendingPathComponent("Scripted.app")
        try FileManager.default.createDirectory(at: scripted.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try Data().write(to: scripted.appendingPathComponent("Contents/Resources/Scripted.sdef"))

        let chromeApp = folder.appendingPathComponent("SoundCloud.app")
        try FileManager.default.createDirectory(at: chromeApp.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try (["CFBundleIdentifier": "com.google.Chrome.app.test", "CrAppModeShortcutURL": "https://soundcloud.com/",
              "CrBundleIdentifier": "com.google.Chrome"] as NSDictionary)
            .write(to: chromeApp.appendingPathComponent("Contents/Info.plist"))

        #expect(CheckedAppTraits.browser(ofAppAt: chromeApp) == "com.google.Chrome")
        #expect(CheckedAppTraits.browser(ofAppAt: electron) == nil)
        #expect(CheckedAppTraits.of(appAt: electron) == CheckedAppTraits(scriptable: false, framework: .electron, needsLaunchOption: true))
        #expect(CheckedAppTraits.of(appAt: scripted) == CheckedAppTraits(scriptable: true, framework: nil, needsLaunchOption: false))
    }
}
