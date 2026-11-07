/// A built-in player keeps no setup: its panel row is remembered while
/// AutoHush runs, never saved (saving one would make it an added app).
struct NoSetups: PlayerSetupStore {
    func setups() -> [PlayerSetup] { [] }
    func save(_ setup: PlayerSetup) {}
    func forget(_ bundleID: String) {}
    func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {}
}
