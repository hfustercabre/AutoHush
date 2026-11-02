import AutoHushKit

/// What tells which supported app is the user's player, read as the welcome
/// window opens, and the tile it picks for them from it (U4b, the user's
/// pick, 2026-11-02): the one playing or in Now Playing, else the one open,
/// else the only one installed. A wrong guess costs a click on another tile.
struct PlayerSignals: Equatable, Sendable {
    /// The supported apps playing sound, or in Now Playing.
    var playing: Set<String> = []
    /// The supported apps open.
    var open: Set<String> = []

    /// The player the welcome window picks among `options` (as it offers
    /// them); `nil` when none is likelier than the others, as with two open
    /// and neither playing. Only a supported app is picked, installed and
    /// tested: never a Safari web app (suggested or added), an app added
    /// with Add an App, or one AntiDot mode keeps from being chosen.
    func likelyPlayer(among options: [PlayerOption]) -> String? {
        let candidates = options
            .filter { $0.kind == .app && $0.isInstalled && $0.isClickable && $0.webAddress == nil && !$0.isUntested }
            .map(\.bundleID)
        // Each signal narrows the next one's apps down: the first that
        // finds any decides, and only when it finds one.
        let tiers = [candidates.filter(playing.contains), candidates.filter(open.contains), candidates]
        guard let found = tiers.first(where: { !$0.isEmpty }), found.count == 1 else { return nil }
        return found.first
    }
}
