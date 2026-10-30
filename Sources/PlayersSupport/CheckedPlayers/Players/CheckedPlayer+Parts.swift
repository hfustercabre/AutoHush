import Foundation
import AutoHushKit
import MenuPlayers
import ScriptablePlayers
import WebAppPlayers

// CheckedPlayer: the players of its setup's ways (`Parts`).
extension CheckedPlayer {
    /// Its ways' players, and which of them read its state, its volume, its
    /// notification.
    struct Parts: Sendable {
        /// The ways, in the setup's order (the panel last): each press goes
        /// to the first that takes it.
        var ways: [any MusicPlayer]
        /// Those that read its state, surest first: its script (when it has
        /// a state), its page, its menu.
        var signs: [any MusicPlayer]
        /// Its script, when it has a volume (fades).
        var volume: any MusicPlayer?
        /// Its script, when it announces each change (its notification).
        var announcing: any MusicPlayer?
        /// Its page's player, whose switch is released with it.
        var page: SafariWebAppPlayer?
        /// The page its panel way reads its player bar through
        /// (`PanelClues.page`), whose switch is released with it too.
        var cluePage: AccessibilityWebPage?
        /// Its panel row doesn't follow it (`PlayerSetup.panelRowIsStale`):
        /// the panel way asks its sound through this.
        var hearing: LateHearing?
        /// What a script that only toggles, with no state of its own, asks before it's sent.
        var toggleState: LateState?
    }

    /// The players of `setup`'s ways.
    static func parts(for setup: PlayerSetup, store: any PlayerSetupStore) -> Parts {
        var parts = Parts(ways: [], signs: [])
        var scripted: ScriptedAppPlayer?, menu: MenuPlayer?
        for way in setup.ways {
            switch way {
            case .script(let script):
                // One that only toggles, with no state, asks the app's other signs.
                let late = script.state == nil ? LateState() : nil
                if let late { parts.toggleState = late }
                let player = ScriptedAppPlayer(bundleID: setup.bundleID, name: setup.name, setup: script,
                                               stateNotification: setup.stateNotification.map { Notification.Name($0) },
                                               toggleState: { await late?.state() ?? .unknown })
                scripted = player
                parts.ways.append(player)
                if script.hasVolume { parts.volume = player }
                if player.stateNotification != nil { parts.announcing = player }
            case .menu(let menuName):
                let player = MenuPlayer(profile: .found(bundleID: setup.bundleID, name: setup.name, menuName: menuName))
                menu = player
                parts.ways.append(player)
            case .page(let access):
                let player = SafariWebAppPlayer(app: SafariWebApp(bundleID: setup.bundleID, name: setup.name, url: setup.appURL),
                                                kind: .app, page: AccessibilityWebPage(access: access), canMute: access.browserID == nil)
                parts.page = player
                parts.ways.append(player)
            case .panel(let remembered):
                let hearing = setup.panelRowIsStale == true ? LateHearing() : nil
                parts.hearing = hearing
                var playerBar: (@Sendable (pid_t) -> [String])?
                if let clue = setup.panelClues?.page {
                    let page = AccessibilityWebPage(access: clue.access), labels = Set(clue.labels)
                    parts.cluePage = page
                    playerBar = { page.playerBarTexts(pid: $0, labels: labels) }
                }
                parts.ways.append(PanelWay(setup: setup, remembered: remembered, store: store, playerBar: playerBar, hearing: hearing))
            case .mute:
                break // a `MutedApp`'s
            }
        }
        if let scripted, scripted.setup.state != nil { parts.signs.append(scripted) }
        if let page = parts.page { parts.signs.append(page) }
        if let menu { parts.signs.append(menu) }
        return parts
    }
}
