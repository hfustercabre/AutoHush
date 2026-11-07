import AppKit
import Foundation
import AutoHushKit
import MenuPlayers
import ScriptablePlayers
import WebAppPlayers

extension BackedUpPlayer {
    /// A built-in player with the backups measured for it: each of its
    /// ways, then the Play/Pause key and the panel last.
    package static func builtIn(_ player: Inner, backups measured: BuiltInBackups,
                                switches: BackupSwitchesStore = BackupSwitchesStore()) -> BackedUpPlayer<Inner> {
        let setup = PlayerSetup(bundleID: player.bundleID, name: player.name, appURL: appURL(of: player), ways: [])
        let keyState = LateState()
        var page: SafariWebAppPlayer?
        var ways: [(CheckedPlayer.Backup, CheckResult.WayResult?)] = []
        for backup in measured.backups where backup.way.kind != .panel {
            switch backup.way {
            case .menu(let menuName):
                let menu = MenuPlayer(profile: .found(bundleID: player.bundleID, name: player.name, menuName: menuName))
                ways.append((CheckedPlayer.Backup(player: menu, kind: .menu), backup.result))
            case .page(let access):
                let learning = SafariWebAppPlayer(app: SafariWebApp(bundleID: player.bundleID, name: player.name, url: setup.appURL),
                                                  kind: .app, page: AccessibilityWebPage(access: access), canMute: false,
                                                  mutesRefusals: { false })
                page = learning
                ways.append((CheckedPlayer.Backup(player: learning, kind: .page), backup.result))
            case .panel: break
            }
        }
        ways.append((CheckedPlayer.Backup(player: MediaKeyWay(bundleID: player.bundleID, name: player.name, state: keyState), kind: .mediaKey), nil))
        let panel = measured.backups.first { $0.way.kind == .panel }
        let song: ScriptedSong? = if case .panel(let song)? = panel?.way { song } else { nil }
        var panelSetup = setup
        panelSetup.panelClues = PanelClues(page: nil, script: song)
        ways.append((CheckedPlayer.Backup(player: PanelWay(setup: panelSetup, remembered: nil, store: NoSetups()), kind: .panel), panel?.result))
        let id = player.bundleID
        return BackedUpPlayer(inner: player, own: CheckResult.WayResult(kind: measured.own, mark: .works),
                              backups: ways.map(\.0), results: ways.map(\.1), learningPage: page, keyState: keyState,
                              switches: { switches.switches(for: id) })
    }

    /// A Safari web app: its page, then the Play/Pause key and the panel,
    /// untested by state (the user, 2026-11-05).
    package static func webApp(_ player: Inner, switches: BackupSwitchesStore = BackupSwitchesStore()) -> BackedUpPlayer<Inner> {
        let setup = PlayerSetup(bundleID: player.bundleID, name: player.name, appURL: appURL(of: player), ways: [])
        let keyState = LateState(), id = player.bundleID
        return BackedUpPlayer(inner: player, own: CheckResult.WayResult(kind: .page, mark: .works),
                              backups: [CheckedPlayer.Backup(player: MediaKeyWay(bundleID: id, name: player.name, state: keyState), kind: .mediaKey),
                                        CheckedPlayer.Backup(player: PanelWay(setup: setup, remembered: nil, store: NoSetups()), kind: .panel)],
                              results: [nil, nil], keyState: keyState, switches: { switches.switches(for: id) })
    }
}

/// Where `player` is installed, as far as is known now (the panel and a
/// page way only need its bundle ID and name).
private func appURL(of player: some MusicPlayer) -> URL {
    player.installedURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleID)
        ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
}
