import AppKit
import Foundation
import AutoHushKit
import WebAppPlayers

/// The apps added through a check, as players: one for each setup, each
/// kept as long as its setup stays the same (a player remembers its page's
/// button and its panel row). An app that isn't installed now is one too,
/// with no `installedURL`, so it's offered as not installed, as a
/// supported app is; one moved since its check gets its new place.
package final class CheckedPlayers: Sendable {
    let store: any PlayerSetupStore
    private let players = KeptPlayers<PlayerSetup, any AddedAppPlayer>(key: { $0.bundleID }, source: { $0.setup })
    /// Where Launch Services finds an app now, by bundle ID; tests stand in for it.
    private let locate: @Sendable (String) -> URL?

    package init(store: any PlayerSetupStore = DefaultsPlayerSetupStore(),
                 locate: @escaping @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.store = store
        self.locate = locate
    }

    package func current() -> [any AddedAppPlayer] {
        players.current(store.setups().map(moved)) { Self.player(for: $0, store: store) }
    }

    /// The player for `setup`: muted instead of paused when that's its way
    /// (Mute It Instead), else pressed by its ways.
    static func player(for setup: PlayerSetup, store: any PlayerSetupStore = DefaultsPlayerSetupStore()) -> any AddedAppPlayer {
        setup.ways.contains(.mute) ? MutedApp(setup: setup) : CheckedPlayer(setup: setup, store: store)
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

    /// Keeps what a check found: its setup, with the way the user chose at
    /// Use, and its page's Play/Pause as a web app's is kept. Nothing when
    /// no way worked.
    /// The app gets a new player, even when its setup didn't change: the
    /// one made before read its page's button as it was made, and doesn't
    /// know the one this check learned (2026-10-18).
    package func keep(_ result: CheckResult, recipes: any PlayPauseRecipeStore = DefaultsRecipeStore()) {
        guard let setup = result.setup else { return }
        if let button = result.pageButton { recipes.save(button, for: setup.bundleID) }
        store.save(setup)
        players.forget(setup.bundleID)
    }

    /// Removes the app added with `bundleID` (the user's Remove…): its setup
    /// and its page's learned button are forgotten, and it's no longer
    /// offered. The app itself stays; a check can add it again.
    package func forget(_ bundleID: String, recipes: any PlayPauseRecipeStore = DefaultsRecipeStore()) {
        store.forget(bundleID)
        recipes.forget(for: bundleID)
        players.forget(bundleID)
    }
}
