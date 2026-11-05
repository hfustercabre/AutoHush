import Testing
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("BackupSwitchesStore")
struct BackupSwitchesStoreTests {
    @Test("a player's switches are both on until set, and kept by bundle ID")
    func switches() {
        let store = BackupSwitchesStore(defaults: MemoryDefaults())
        #expect(store.switches(for: "com.example.jukebox") == BackupSwitches())
        store.set(BackupSwitches(usesBackups: true, panelWhileMuted: false), for: "com.example.jukebox")
        #expect(store.switches(for: "com.example.jukebox") == BackupSwitches(usesBackups: true, panelWhileMuted: false))
        #expect(store.switches(for: "com.example.other") == BackupSwitches())
        // The main control chosen in Settings is kept with them; none, its own.
        store.set(BackupSwitches(mainControl: "menu"), for: "com.example.jukebox")
        #expect(store.switches(for: "com.example.jukebox").mainControl == "menu")
        store.set(BackupSwitches(), for: "com.example.jukebox")
        #expect(store.switches(for: "com.example.jukebox").mainControl == nil)
    }
}
