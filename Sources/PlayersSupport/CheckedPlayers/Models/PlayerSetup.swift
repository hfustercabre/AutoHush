import Foundation
import AutoHushKit
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
    var appURL: URL
    /// The surest first, the panel, if any, last: in a check's result, the
    /// ways that worked; kept, only the one the user chose at Use (an older
    /// setup may hold several, tried in that order).
    package var ways: [Way]
    /// The notification that announced its pauses and plays in the check.
    var stateNotification: String?
    /// An Electron app that takes presses while covered or on another desktop
    /// only when opened with `--disable-backgrounding-occluded-windows`: the
    /// user is asked before AutoHush reopens it so (2026-10-15).
    var needsLaunchOption: Bool
    /// Its Now Playing row shows a state it doesn't follow (Qobuz's always
    /// shows paused, 2026-10-16), as its check found: when its sound says
    /// otherwise, the row is pressed as a toggle (`PanelWay`), so only its
    /// sound tells, and AntiDot mode, which hears none, can't control it.
    package var panelRowIsStale: Bool?
    /// Where its song shows besides its windows' titles, as its check found
    /// it, which tells its Now Playing row (`PanelWay`); `nil` without the
    /// panel, or with nothing more than its titles.
    var panelClues: PanelClues?

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
