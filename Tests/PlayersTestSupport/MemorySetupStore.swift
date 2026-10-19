import AutoHushTestSupport
import CheckedPlayers

/// The setups of the apps added with Add an App, kept in memory as the
/// preferences keep them: by bundle ID, read by name.
package final class MemorySetupStore: PlayerSetupStore {
    private let kept = Locked<[String: PlayerSetup]>([:])

    package init() {}

    package func setups() -> [PlayerSetup] {
        kept.value.values.sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    package func save(_ setup: PlayerSetup) { kept.withLock { $0[setup.bundleID] = setup } }
    package func forget(_ bundleID: String) { kept.withLock { $0[bundleID] = nil } }
}
