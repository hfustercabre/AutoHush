import AppKit
import Foundation
import os
import AutoHushKit
import WebAppPlayers

/// The apps added through a check, as players: one for each setup, each
/// kept as long as its setup stays the same (a player remembers its page's
/// button and its panel row). An app that isn't installed now is one too,
/// with no `installedURL`, so it's offered as not installed, as a
/// supported app is; one moved since its check gets its new place.
package final class CheckedPlayers: Sendable {
    let store: any PlayerSetupStore
    private let players = OSAllocatedUnfairLock<[String: CheckedPlayer]>(initialState: [:])
    /// Where Launch Services finds an app now, by bundle ID; tests stand in for it.
    private let locate: @Sendable (String) -> URL?

    package init(store: any PlayerSetupStore = DefaultsPlayerSetupStore(),
                 locate: @escaping @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.store = store
        self.locate = locate
    }

    package func current() -> [CheckedPlayer] {
        let setups = store.setups().map(moved)
        // New players are made outside the lock: each reads its page's
        // learned button from the preferences as it's made.
        let known = players.withLock { $0 }
        let made = Dictionary(setups.filter { known[$0.bundleID]?.setup != $0 }.map { ($0.bundleID, CheckedPlayer(setup: $0, store: store)) },
                              uniquingKeysWith: { first, _ in first })
        return players.withLock { players in
            // A player another call kept meanwhile wins, so each app has one.
            let latest = players
            players = [:]
            return setups.compactMap { setup in
                guard let player = [latest[setup.bundleID], known[setup.bundleID], made[setup.bundleID]]
                    .lazy.compactMap({ $0 }).first(where: { $0.setup == setup })
                else { return nil } // never: a known player matches, or one was made
                players[setup.bundleID] = player
                return player
            }
        }
    }

    /// `setup`, at its app's new place when it was moved since its check
    /// (kept so); as it is when it's there, or isn't installed.
    private func moved(_ setup: PlayerSetup) -> PlayerSetup {
        guard !FileManager.default.fileExists(atPath: setup.appURL.path), let url = locate(setup.bundleID), url != setup.appURL
        else { return setup }
        var moved = setup
        moved.appURL = url
        store.update(setup.bundleID) { $0.appURL = url }
        return moved
    }

    /// Keeps what a check found: the setup of the ways that worked, and its
    /// page's Play/Pause as a web app's is kept. Nothing when none worked.
    package func keep(_ result: CheckResult, recipes: any PlayPauseRecipeStore = DefaultsRecipeStore()) {
        guard let setup = result.setup else { return }
        if let button = result.pageButton { recipes.save(button, for: setup.bundleID) }
        store.save(setup)
    }

    /// Removes the app added with `bundleID` (the user's Remove…): its setup
    /// and its page's learned button are forgotten, and it's no longer
    /// offered. The app itself stays; a check can add it again.
    package func forget(_ bundleID: String, recipes: any PlayPauseRecipeStore = DefaultsRecipeStore()) {
        store.forget(bundleID)
        recipes.forget(for: bundleID)
        players.withLock { $0[bundleID] = nil }
    }
}
