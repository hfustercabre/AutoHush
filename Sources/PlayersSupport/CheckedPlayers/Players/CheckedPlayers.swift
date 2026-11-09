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
    /// Kept by their setup with their backup switches as they are now
    /// (`CheckedPlayer.setupNow`): Settings changing them keeps the player.
    private let players = KeptPlayers<KeptSetup, any AddedAppPlayer>(key: { $0.setup.bundleID },
                                                                     source: { KeptSetup(($0 as? CheckedPlayer)?.setupNow ?? $0.setup) })
    /// Where Launch Services finds an app now, by bundle ID; tests stand in for it.
    private let locate: @Sendable (String) -> URL?

    package init(store: any PlayerSetupStore = DefaultsPlayerSetupStore(),
                 locate: @escaping @Sendable (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }) {
        self.store = store
        self.locate = locate
    }

    package func current() -> [any AddedAppPlayer] {
        players.current(store.setups().map { KeptSetup(moved($0)) }) { Self.player(for: $0.setup, store: store) }
    }

    /// A setup as a player is kept by: the same whatever panel row it
    /// remembers, which its player saves itself at each new song, so the
    /// player stays (the 2026-11-06 full check's K4-7).
    private struct KeptSetup: Equatable, Sendable {
        let setup: PlayerSetup

        init(_ setup: PlayerSetup) { self.setup = setup }

        static func == (lhs: KeptSetup, rhs: KeptSetup) -> Bool {
            lhs.withoutPanelRow == rhs.withoutPanelRow
        }

        private var withoutPanelRow: PlayerSetup {
            var setup = setup
            setup.ways = setup.ways.map { $0.isPanel ? .panel(rememberedRow: nil) : $0 }
            setup.backups = setup.backups.map { $0.isPanel ? .panel(rememberedRow: nil) : $0 }
            return setup
        }
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

    /// The backup switches of the app added with `bundleID`, once checked
    /// since backup controls were kept; `nil` otherwise.
    package func switches(for bundleID: String) -> BackupSwitches? {
        guard let setup = store.setups().first(where: { $0.bundleID == bundleID }), !setup.wayResults.isEmpty else { return nil }
        return setup.switches
    }

    /// Sets the backup switches and main control of the app added with
    /// `bundleID` (Settings → Fine-Tuning): its setup keeps them, and its
    /// player follows them from its next press, the same player (a new one
    /// would drop a pause AutoHush holds in it; the user, 2026-11-05). `player` is the one in
    /// use, which may no longer be the one kept (made again once its setup
    /// changed or its app moved). The players first,
    /// so the kept one still matches its setup once that's saved.
    package func setSwitches(_ switches: BackupSwitches, for bundleID: String, player: (any AddedAppPlayer)? = nil) {
        for used in [player, players.kept(bundleID)] { (used as? CheckedPlayer)?.setSwitches(switches) }
        store.update(bundleID) {
            $0.usesBackups = switches.usesBackups
            $0.panelWhileMuted = switches.panelWhileMuted
            $0.mainControl = switches.mainControl
        }
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
