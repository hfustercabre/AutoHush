import Foundation
import ScriptablePlayers
import WebAppPlayers

/// What a check found for an app AutoHush has no module for: the ways to
/// pause and play it (kept, the one the user chose), and what reads its
/// state. Kept (`PlayerSetupStore`), so the app is offered as a player from
/// then on (the user, 2026-10-15: apps are added through Player Check).
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
        /// Its row in the menu bar's Now Playing panel; the row it changed
        /// with last.
        case panel(rememberedRow: String?)
        /// Muting it while other apps play, never pausing it: chosen in Add
        /// an App when no way worked (the user, 2026-10-15). It keeps playing,
        /// silent, and is heard again when they stop.
        case mute

        /// Which of the check's ways it is; none for muting.
        package var kind: CheckResult.WayKind? {
            switch self {
            case .script: .script
            case .menu: .menu
            case .page: .page
            case .panel: .panel
            case .mute: nil
            }
        }
    }

    package var bundleID: String
    package var name: String
    /// Where the app was when it was checked.
    package var appURL: URL
    /// The surest first, the panel, if any, last: in a check's result, the
    /// ways that worked; kept, only the one the user chose at Use (an older
    /// setup may hold several, tried in that order).
    package var ways: [Way]
    /// The notification that announced its pauses and plays in the check.
    package var stateNotification: String?
    /// An Electron app that takes presses while covered or on another desktop
    /// only when opened with `--disable-backgrounding-occluded-windows`: the
    /// user is asked before AutoHush reopens it so (2026-10-15).
    package var needsLaunchOption: Bool
    /// Its Now Playing row shows a state it doesn't follow (Qobuz's always
    /// shows paused, 2026-10-16), as its check found: when its sound says
    /// otherwise, the row is pressed as a toggle (`PanelWay`), so only its
    /// sound tells, and AntiDot mode, which hears none, can't control it.
    package var panelRowIsStale: Bool?
    /// Where its song shows besides its windows' titles, as its check found
    /// it, which tells its Now Playing row (`PanelWay`); `nil` without the
    /// panel, or with nothing more than its titles.
    package var panelClues: PanelClues?

    package init(bundleID: String, name: String, appURL: URL, ways: [Way], stateNotification: String? = nil,
                 needsLaunchOption: Bool = false, panelRowIsStale: Bool? = nil, panelClues: PanelClues? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.appURL = appURL
        self.ways = ways.sorted { ($0.isPanel ? 1 : 0) < ($1.isPanel ? 1 : 0) }
        self.stateNotification = stateNotification
        self.needsLaunchOption = needsLaunchOption
        self.panelRowIsStale = panelRowIsStale
        self.panelClues = panelClues
    }
}

extension PlayerSetup {
    /// The option an Electron app is opened with so its page takes presses
    /// while its window is covered or on another desktop.
    package static let launchOption = "--disable-backgrounding-occluded-windows"
}

extension PlayerSetup.Way {
    package var isPanel: Bool { if case .panel = self { true } else { false } }
}

/// Where setups are kept. A protocol, so tests can keep them in memory.
package protocol PlayerSetupStore: Sendable {
    func setups() -> [PlayerSetup]
    func save(_ setup: PlayerSetup)
    func forget(_ bundleID: String)
    /// Changes the kept setup of `bundleID`, if one is kept (a setup the
    /// user removed isn't added back).
    func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void)
}

extension PlayerSetupStore {
    /// Read, changed and saved in turn; the preferences' store does it
    /// under its lock.
    package func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {
        guard var setup = setups().first(where: { $0.bundleID == bundleID }) else { return }
        change(&setup)
        save(setup)
    }
}

/// The setups in AutoHush's preferences, each as JSON by bundle ID.
package struct DefaultsPlayerSetupStore: PlayerSetupStore {
    package static let key = "checkedPlayerSetups"
    private static let lock = NSLock()
    /// The preferences' suite; `nil` for AutoHush's own (tests use one of theirs).
    private let suiteName: String?

    package init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// The setups that can be read, by name; one that can't is left out.
    package func setups() -> [PlayerSetup] {
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Data] ?? [:]
        return stored.values.compactMap { try? JSONDecoder().decode(PlayerSetup.self, from: $0) }
            .sorted { $0.name.localizedLowercase < $1.name.localizedLowercase }
    }

    package func save(_ setup: PlayerSetup) {
        guard let data = try? JSONEncoder().encode(setup) else { return }
        let defaults = defaults
        Self.lock.withLock {
            var stored = defaults.dictionary(forKey: Self.key) ?? [:]
            stored[setup.bundleID] = data
            defaults.set(stored, forKey: Self.key)
        }
    }

    package func forget(_ bundleID: String) {
        let defaults = defaults
        Self.lock.withLock {
            var stored = defaults.dictionary(forKey: Self.key) ?? [:]
            guard stored.removeValue(forKey: bundleID) != nil else { return }
            defaults.set(stored, forKey: Self.key)
        }
    }

    /// Read, changed and saved under the lock: a change (a panel row kept,
    /// a moved app's place) can't bring back a setup the user removed
    /// meanwhile, nor put its old ways over a new check's.
    package func update(_ bundleID: String, _ change: (inout PlayerSetup) -> Void) {
        let defaults = defaults
        Self.lock.withLock {
            var stored = defaults.dictionary(forKey: Self.key) ?? [:]
            guard let data = stored[bundleID] as? Data, var setup = try? JSONDecoder().decode(PlayerSetup.self, from: data) else { return }
            change(&setup)
            guard let changed = try? JSONEncoder().encode(setup) else { return }
            stored[bundleID] = changed
            defaults.set(stored, forKey: Self.key)
        }
    }
}
