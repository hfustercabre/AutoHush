import Foundation

/// The music players the user chooses from, in the order they are offered.
/// AutoHush controls one of them at a time: the one the user chose.
package struct MusicPlayerCatalog: Sendable {
    package let players: [any MusicPlayer]
    /// The player AutoHush controlled before it could be chosen: people
    /// updating from such a version keep it without being asked.
    package let formerDefault: String?

    package init(players: [any MusicPlayer], formerDefault: String? = nil) {
        self.players = players
        self.formerDefault = formerDefault
    }

    /// The player with this bundle ID; `nil` for one not in the catalog.
    package func player(bundleID: String?) -> (any MusicPlayer)? {
        guard let bundleID else { return nil }
        return players.first { $0.bundleID == bundleID }
    }
}
