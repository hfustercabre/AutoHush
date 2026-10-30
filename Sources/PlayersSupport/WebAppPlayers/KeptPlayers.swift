import os

/// Players kept one per app (by bundle ID), each for as long as what it was
/// made from stays the same: a player remembers what it learned (its page's
/// button, how learning goes, its panel row). The Safari web apps' and the
/// apps added through a check keep theirs so.
package final class KeptPlayers<Source: Equatable & Sendable, Player: Sendable>: Sendable {
    private let players = OSAllocatedUnfairLock<[String: Player]>(initialState: [:])
    /// The bundle ID of the app `Source` makes a player of.
    private let key: @Sendable (Source) -> String
    /// What a player was made from.
    private let source: @Sendable (Player) -> Source

    package init(key: @escaping @Sendable (Source) -> String, source: @escaping @Sendable (Player) -> Source) {
        self.key = key
        self.source = source
    }

    /// A player for each of `sources`, in their order: the one kept for its
    /// app while it was made from the same, else a new one (`make`).
    package func current(_ sources: [Source], make: (Source) -> Player) -> [Player] {
        let (key, source) = (key, source)
        // New players are made outside the lock: each reads what it learned
        // from the preferences as it's made.
        let known = players.withLock { $0 }
        let made = Dictionary(sources.filter { known[key($0)].map(source) != $0 }.map { (key($0), make($0)) },
                              uniquingKeysWith: { first, _ in first })
        return players.withLock { players in
            // A player another call kept meanwhile wins, so each app has one.
            let latest = players
            players = [:]
            return sources.compactMap { wanted in
                guard let player = [latest[key(wanted)], known[key(wanted)], made[key(wanted)]]
                    .lazy.compactMap({ $0 }).first(where: { source($0) == wanted })
                else { return nil } // never: a known player matches, or one was made
                players[key(wanted)] = player
                return player
            }
        }
    }

    /// Forgets the player kept for the app with `bundleID`: the next
    /// `current` makes a new one.
    package func forget(_ bundleID: String) {
        players.withLock { $0[bundleID] = nil }
    }
}
