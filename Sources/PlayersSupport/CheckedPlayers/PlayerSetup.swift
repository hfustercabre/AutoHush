import Foundation
import ScriptablePlayers
import WebAppPlayers

/// What a check found for an app AutoHush has no module for: the ways that
/// paused and played it, the surest first, and what reads its state. Kept
/// (`PlayerSetupStore`), so the app is offered as a player from then on
/// (the user, 2026-10-15: apps are added through Player Check).
package struct PlayerSetup: Codable, Equatable, Sendable {
    /// A way to pause and play it, as the check tried them.
    package enum Way: Codable, Equatable, Sendable {
        /// Its AppleScript commands (`ScriptedAppPlayer`).
        case script(ScriptSetup)
        /// Its playback menu's first item (`MenuPlayer`), found as AutoHush
        /// finds any; `menuName` for the log.
        case menu(menuName: String)
        /// Its page's Play/Pause (`SafariWebAppPlayer` with `PageAccess`); the
        /// button the check learned is kept as a web app's is.
        case page(PageAccess)
        /// Its row in the menu bar's Now Playing panel: only when nothing else
        /// works (the user, 2026-10-15); the row it changed with last.
        case panel(rememberedRow: String?)
        /// Muting it while other apps play, never pausing it: chosen in Add
        /// an App when no way worked (the user, 2026-10-15). It keeps playing,
        /// silent, and is heard again when they stop.
        case mute
    }

    package var bundleID: String
    package var name: String
    /// Where the app was when it was checked.
    package var appURL: URL
    /// The ways that worked, the surest first; the panel, if any, last.
    package var ways: [Way]
    /// The notification that announced its pauses and plays in the check.
    package var stateNotification: String?
    /// An Electron app that takes presses while covered or on another desktop
    /// only when opened with `--disable-backgrounding-occluded-windows`: the
    /// user is asked before AutoHush reopens it so (2026-10-15).
    package var needsLaunchOption: Bool

    package init(bundleID: String, name: String, appURL: URL, ways: [Way], stateNotification: String? = nil,
                 needsLaunchOption: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.appURL = appURL
        self.ways = ways.sorted { ($0.isPanel ? 1 : 0) < ($1.isPanel ? 1 : 0) }
        self.stateNotification = stateNotification
        self.needsLaunchOption = needsLaunchOption
    }
}

extension PlayerSetup.Way {
    package var isPanel: Bool { if case .panel = self { true } else { false } }
}

/// Where setups are kept. A protocol, so tests can keep them in memory.
package protocol PlayerSetupStore: Sendable {
    func setups() -> [PlayerSetup]
    func save(_ setup: PlayerSetup)
    func forget(_ bundleID: String)
}

/// The setups in AutoHush's preferences, each as JSON by bundle ID.
package struct DefaultsPlayerSetupStore: PlayerSetupStore {
    package static let key = "checkedPlayerSetups"
    private static let lock = NSLock()

    package init() {}

    package func setups() -> [PlayerSetup] {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Data] ?? [:]
        return stored.values.compactMap { try? JSONDecoder().decode(PlayerSetup.self, from: $0) }
            .sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    package func save(_ setup: PlayerSetup) {
        guard let data = try? JSONEncoder().encode(setup) else { return }
        Self.lock.withLock {
            var stored = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
            stored[setup.bundleID] = data
            UserDefaults.standard.set(stored, forKey: Self.key)
        }
    }

    package func forget(_ bundleID: String) {
        Self.lock.withLock {
            var stored = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
            guard stored.removeValue(forKey: bundleID) != nil else { return }
            UserDefaults.standard.set(stored, forKey: Self.key)
        }
    }
}
