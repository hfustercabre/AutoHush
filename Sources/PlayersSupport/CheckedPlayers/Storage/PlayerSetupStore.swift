/// Where setups are kept. A protocol, so tests can keep them in memory.
package protocol PlayerSetupStore: Sendable {
    func setups() -> [PlayerSetup]
    func save(_ setup: PlayerSetup)
    func forget(_ bundleID: String)
    /// Changes the kept setup of `bundleID`, if one is kept (a setup the
    /// user removed isn't added back).
    func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void)
}

extension PlayerSetupStore {
    /// Read, changed and saved in turn; the preferences' store does it
    /// under its lock.
    package func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {
        guard var setup = setups().first(where: { $0.bundleID == bundleID }) else { return }
        change(&setup)
        save(setup)
    }
}
