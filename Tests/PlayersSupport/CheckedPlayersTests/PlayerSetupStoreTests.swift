import Foundation
import Testing
@testable import CheckedPlayers

@Suite("DefaultsPlayerSetupStore")
struct PlayerSetupStoreTests {
    private func setup(_ id: String, _ name: String) -> PlayerSetup {
        PlayerSetup(bundleID: id, name: name, appURL: URL(fileURLWithPath: "/Applications/\(name).app"), ways: [.menu(menuName: "Play")])
    }

    /// A store in a suite of its own, removed after.
    private func withStore(_ body: (DefaultsPlayerSetupStore, UserDefaults) throws -> Void) rethrows {
        let suite = "AutoHush.PlayerSetupStoreTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try body(DefaultsPlayerSetupStore(suiteName: suite), UserDefaults(suiteName: suite)!)
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
}
