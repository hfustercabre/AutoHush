import Foundation

/// The music players the user chooses from, in the order they are offered.
/// AutoHush controls one of them at a time: the one the user chose.
package struct MusicPlayerCatalog: Sendable {
    /// The players AutoHush ships with.
    package let players: [any MusicPlayer]
    /// The player AutoHush controlled before it could be chosen: people
    /// updating from such a version keep it without being asked.
    package let formerDefault: String?
    /// Players found on this Mac besides those (its Safari web apps), looked
    /// up afresh each time; each app keeps its instance.
    private let found: @Sendable () -> [any MusicPlayer]

    package init(
        players: [any MusicPlayer],
        formerDefault: String? = nil,
        found: @escaping @Sendable () -> [any MusicPlayer] = { [] }
    ) {
        self.players = players
        self.formerDefault = formerDefault
        self.found = found
    }

    /// Every player to choose from now: the built-in ones, then those found.
    package var all: [any MusicPlayer] { players + found() }

    /// The player with this bundle ID; `nil` for one not in the catalog.
    package func player(bundleID: String?) -> (any MusicPlayer)? {
        guard let bundleID else { return nil }
        return all.first { $0.bundleID == bundleID }
    }
}
