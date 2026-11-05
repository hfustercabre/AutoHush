import Foundation
import os
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
        /// Its backups' that read its state, in the same order: asked after
        /// its own and its Now Playing report (the user, 2026-11-04), so a
        /// backup page with no window, which says stopped, can't speak over
        /// them.
        var backupSigns: [any MusicPlayer] = []
        /// Its backups' players, in the setup's order (the panel last), then
        /// the Play/Pause key (`hasMediaKey`), with its backups on: pressed
        /// by the window's state (`CheckedPlayer+Backups`).
        var backups: [Backup] = []
        /// Its script, when it has a volume (fades).
        var volume: any MusicPlayer?
        /// Its script, when it announces each change (its notification).
        var announcing: any MusicPlayer?
        /// Its page's player, whose switch is released with it.
        var page: SafariWebAppPlayer?
        /// Its page is a backup: it mutes nothing new while they're off.
        var pageIsBackup = false
        /// The page its panel way reads its player bar through
        /// (`PanelClues.page`), whose switch is released with it too.
        var cluePage: AccessibilityWebPage?
        /// Its panel row doesn't follow it (`PlayerSetup.panelRowIsStale`):
        /// the panel way asks its sound through this.
        var hearing: LateHearing?
        /// The same for a panel kept as a backup: only that way listens to
        /// it, so the app isn't told by its level (`hearing`) for it.
        var backupHearing: LateHearing?
        /// What a script that only toggles, with no state of its own, asks before it's sent.
        var toggleState: LateState?
        /// What the Play/Pause key asks before it's pressed, and to judge it.
        var mediaKeyState: LateState?
    }

    /// The players of `setup`'s ways and of its backups, the Play/Pause key
    /// after them, made whether its backups are on or not (`switches`, read
    /// at each press): a backup's sign tells its state too while they're on
    /// (the user, 2026-11-04), but only the chosen way fades it and
    /// announces its changes.
    static func parts(for setup: PlayerSetup, store: any PlayerSetupStore,
                      switches: OSAllocatedUnfairLock<BackupSwitches>? = nil) -> Parts {
        let switches = switches ?? OSAllocatedUnfairLock(initialState: setup.switches)
        var parts = Parts(ways: [], signs: [])
        var scripted: ScriptedAppPlayer?, menu: MenuPlayer?
        var backupKinds: Set<CheckResult.WayKind> = []
        let backups = setup.backups
        for (index, way) in (setup.ways + backups).enumerated() {
            let isBackup = index >= setup.ways.count
            let player: any MusicPlayer
            switch way {
            case .script(let script):
                // One that only toggles, with no state, asks the app's other signs.
                let late = script.state == nil ? LateState() : nil
                if let late { parts.toggleState = late }
                let scriptPlayer = ScriptedAppPlayer(bundleID: setup.bundleID, name: setup.name, setup: script,
                                                     stateNotification: isBackup ? nil : setup.stateNotification.map { Notification.Name($0) },
                                                     toggleState: { await late?.state() ?? .unknown })
                scripted = scriptPlayer
                player = scriptPlayer
                if !isBackup, script.hasVolume { parts.volume = scriptPlayer }
                if scriptPlayer.stateNotification != nil { parts.announcing = scriptPlayer }
            case .menu(let menuName):
                let menuPlayer = MenuPlayer(profile: .found(bundleID: setup.bundleID, name: setup.name, menuName: menuName))
                menu = menuPlayer
                player = menuPlayer
            case .page(let access):
                let page = SafariWebAppPlayer(app: SafariWebApp(bundleID: setup.bundleID, name: setup.name, url: setup.appURL),
                                              kind: .app, page: AccessibilityWebPage(access: access),
                                              canMute: access.browserID == nil,
                                              mutesRefusals: { [backedUp = !backups.isEmpty || hasMediaKey(setup)] in
                                                  pageMutesItself(access, backedUp: backedUp && switches.withLock { $0.usesBackups })
                                              })
                parts.page = page
                parts.pageIsBackup = isBackup
                player = page
            case .panel(let remembered):
                let hearing = setup.panelRowIsStale == true ? LateHearing() : nil
                if isBackup { parts.backupHearing = hearing } else { parts.hearing = hearing }
                var playerBar: (@Sendable (pid_t) -> [String])?
                if let clue = setup.panelClues?.page {
                    let page = AccessibilityWebPage(access: clue.access), labels = Set(clue.labels)
                    parts.cluePage = page
                    playerBar = { page.playerBarTexts(pid: $0, labels: labels) }
                }
                player = PanelWay(setup: setup, remembered: remembered, store: store, playerBar: playerBar, hearing: hearing)
            case .mute:
                continue // a `MutedApp`'s
            }
            if isBackup, let kind = way.kind {
                parts.backups.append(Backup(player: player, kind: WayOrder.Kind(kind)))
                backupKinds.insert(kind)
            } else {
                parts.ways.append(player)
            }
        }
        if hasMediaKey(setup) {
            let state = LateState()
            parts.mediaKeyState = state
            parts.backups.append(Backup(player: MediaKeyWay(bundleID: setup.bundleID, name: setup.name, state: state), kind: .mediaKey))
        }
        func sign(_ player: (any MusicPlayer)?, _ kind: CheckResult.WayKind) {
            guard let player else { return }
            if backupKinds.contains(kind) { parts.backupSigns.append(player) } else { parts.signs.append(player) }
        }
        sign(scripted?.setup.state != nil ? scripted : nil, .script)
        sign(parts.page, .page)
        sign(menu, .menu)
        return parts
    }

    /// Whether its page mutes the app itself when its pause is refused (its
    /// mute while an ad plays, its button saying paused, stays): not
    /// a Chromium web app's, which plays through its browser (muting it would
    /// mute every tab), nor one with backups in use, the Play/Pause key
    /// alone included, whose refusal goes to AutoHush's mute, which tries
    /// them meanwhile (the user, 2026-11-04).
    static func pageMutesItself(_ access: PageAccess, backedUp: Bool) -> Bool {
        access.browserID == nil && !backedUp
    }
}
