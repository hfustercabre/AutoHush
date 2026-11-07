import Foundation
import AutoHushKit
import ScriptablePlayers
import Testing
import AutoHushTestSupport
@testable import CheckedPlayers
import WebAppPlayers

@Suite("DefaultsPlayerSetupStore")
struct PlayerSetupStoreTests {
    private func setup(_ id: String, _ name: String) -> PlayerSetup {
        PlayerSetup(bundleID: id, name: name, appURL: URL(fileURLWithPath: "/Applications/\(name).app"), ways: [.menu(menuName: "Play")])
    }

    /// A store with preferences of its own, in memory.
    private func withStore(_ body: (DefaultsPlayerSetupStore, UserDefaults) throws -> Void) rethrows {
        let defaults = MemoryDefaults()
        try body(DefaultsPlayerSetupStore(defaults: defaults), defaults)
    }

    @Test("setups are kept by bundle ID, read by name; forgotten, gone")
    func keeps() {
        withStore { store, _ in
            store.save(setup("com.example.b", "beta"))
            store.save(setup("com.example.a", "Alpha"))
            store.save(setup("com.example.b", "Beta"))
            #expect(store.setups().map(\.name) == ["Alpha", "Beta"])
            store.forget("com.example.a")
            store.forget("com.example.none")
            #expect(store.setups().map(\.bundleID) == ["com.example.b"])
        }
    }

    @Test("a change goes to a kept setup only")
    func updates() {
        withStore { store, _ in
            store.update("com.example.a") { $0.name = "Never" }
            #expect(store.setups().isEmpty)
            store.save(setup("com.example.a", "Alpha"))
            store.update("com.example.a") { $0.needsLaunchOption = true }
            #expect(store.setups().first?.needsLaunchOption == true)
        }
    }

    @Test("one that can't be read is left out, the others kept")
    func unreadable() {
        withStore { store, defaults in
            store.save(setup("com.example.a", "Alpha"))
            var stored = defaults.dictionary(forKey: DefaultsPlayerSetupStore.key) ?? [:]
            stored["com.example.broken"] = Data("not a setup".utf8)
            defaults.set(stored, forKey: DefaultsPlayerSetupStore.key)
            #expect(store.setups().map(\.bundleID) == ["com.example.a"])
        }
    }

    @Test("a panel's clues are kept with its setup; one kept before them reads as having none")
    func panelClues() throws {
        var kept = setup("com.example.a", "Alpha")
        kept.ways = [.panel(rememberedRow: "Song, Artist – Album")]
        kept.panelClues = PanelClues(page: PanelClues.Page(access: PageAccess(interface: .electron, switchAttribute: PageAccess.electronSwitch),
                                                           labels: ["Pause"]), script: .property("vlcN"))
        withStore { store, _ in
            store.save(kept)
            #expect(store.setups() == [kept])
        }
        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any] ?? [:]
        older["panelClues"] = nil
        let read = try JSONDecoder().decode(PlayerSetup.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(read.panelClues == nil && read.ways == kept.ways)
    }

    @Test("its backups (the panel last), how each way did in each window state, both switches and its main control are kept; one kept before them reads with none, backups on and the panel while muted off; ones it can't read are left out, the app kept")
    func backups() throws {
        let electron = PageAccess(interface: .electron, switchAttribute: PageAccess.electronSwitch)
        var kept = PlayerSetup(bundleID: "com.example.a", name: "Alpha", appURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
                               ways: [.menu(menuName: "Play")], backups: [.panel(rememberedRow: nil), .page(electron)])
        #expect(kept.backups == [.page(electron), .panel(rememberedRow: nil)] && kept.usesBackups && !kept.panelWhileMuted)
        kept.wayResults = [
            CheckResult.WayResult(kind: .menu, mark: .works, states: [.init(state: .visible, outcome: .worked)]),
            CheckResult.WayResult(kind: .page, mark: .some, failedStates: [.hidden],
                                  states: [.init(state: .visible, outcome: .worked), .init(state: .hidden, outcome: .failed, reason: "not found")]),
        ]
        // Away from the defaults, so one not kept fails.
        kept.usesBackups = false
        kept.panelWhileMuted = true
        kept.mainControl = "page"
        withStore { store, _ in
            store.save(kept)
            #expect(store.setups() == [kept])
        }
        var older = try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any] ?? [:]
        for key in ["backups", "wayResults", "usesBackups", "panelWhileMuted", "mainControl"] { older[key] = nil }
        let read = try JSONDecoder().decode(PlayerSetup.self, from: JSONSerialization.data(withJSONObject: older))
        #expect(read.ways == kept.ways && read.backups.isEmpty && read.wayResults.isEmpty && read.usesBackups && !read.panelWhileMuted
                && read.mainControl == nil)

        // A later AutoHush's way or window state in them, read here: none, the app kept.
        var later = try JSONSerialization.jsonObject(with: JSONEncoder().encode(kept)) as? [String: Any] ?? [:]
        later["backups"] = [["mediaKey": [String: Any]()]]
        later["wayResults"] = [["kind": "page", "mark": "some", "failedStates": ["onTheMoon"], "states": [[String: Any]]()]]
        let unknown = try JSONDecoder().decode(PlayerSetup.self, from: JSONSerialization.data(withJSONObject: later))
        #expect(unknown.ways == kept.ways && unknown.backups.isEmpty && unknown.wayResults.isEmpty && !unknown.usesBackups)
    }

    @Test("a setup written before its switches were held together reads back exactly as before, and is written as before: each switch and its main control a key of its own")
    func switchesAsBefore() throws {
        let older: [String: Any] = [
            "bundleID": "com.example.a", "name": "Alpha", "appURL": "file:///Applications/Alpha.app",
            "ways": [["menu": ["menuName": "Play"]]], "backups": [["panel": [String: Any]()]], "wayResults": [[String: Any]](),
            "usesBackups": false, "panelWhileMuted": true, "mainControl": "panel", "needsLaunchOption": false,
        ]
        let read = try JSONDecoder().decode(PlayerSetup.self, from: JSONSerialization.data(withJSONObject: older))
        var expected = PlayerSetup(bundleID: "com.example.a", name: "Alpha", appURL: URL(fileURLWithPath: "/Applications/Alpha.app"),
                                   ways: [.menu(menuName: "Play")], backups: [.panel(rememberedRow: nil)],
                                   usesBackups: false, panelWhileMuted: true)
        expected.mainControl = "panel"
        #expect(read == expected)
        #expect(read.switches == BackupSwitches(usesBackups: false, panelWhileMuted: true, mainControl: "panel"))
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(read)) as? NSDictionary
        #expect(written == older as NSDictionary)
    }
}
