import AppKit
import Foundation
import os
import AutoHushKit

/// The apps added through a check, as players: one for each setup whose app
/// is installed, each kept as long as its setup stays the same (a player
/// remembers its page's button and its panel row).
package final class CheckedPlayers: Sendable {
    let store: any PlayerSetupStore
    private let players = OSAllocatedUnfairLock<[String: CheckedPlayer]>(initialState: [:])

    package init(store: any PlayerSetupStore = DefaultsPlayerSetupStore()) {
        self.store = store
    }

    package func current() -> [CheckedPlayer] {
        let setups = store.setups().filter {
            FileManager.default.fileExists(atPath: $0.appURL.path)
                || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil
        }
        return players.withLock { players in
            let known = players
            players = [:]
            return setups.map { setup in
                let player = known[setup.bundleID].flatMap { $0.setup == setup ? $0 : nil } ?? CheckedPlayer(setup: setup, store: store)
                players[setup.bundleID] = player
                return player
            }
        }
    }
}
