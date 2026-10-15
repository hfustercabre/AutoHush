import AppKit
import Foundation
import AutoHushKit
import MenuPlayers

/// Pausing and playing an app through its row in the menu bar's Now Playing
/// panel: the last way (the user, 2026-10-15), since the panel shows on
/// screen for about half a second and takes the keyboard. Its row is the one
/// showing what the app plays (its windows' titles) or its name, else the
/// row it changed with last (kept in its setup), else, pausing, the only one
/// playing while it holds Now Playing. Its state comes from its other signs.
package actor PanelWay: MusicPlayer {
    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated var controlPermission: Permission { .accessibility(player: name) }
    package nonisolated var canFade: Bool { false }
    private var setup: PlayerSetup
    private var remembered: String?
    private let store: any PlayerSetupStore
    private let panel: any NowPlayingPanel
    private let queue = DispatchQueue(label: "AutoHush.NowPlayingPanel", qos: .userInitiated)

    package init(setup: PlayerSetup, remembered: String?, store: any PlayerSetupStore,
                 panel: any NowPlayingPanel = AccessibilityNowPlayingPanel()) {
        bundleID = setup.bundleID
        name = setup.name
        self.setup = setup
        self.remembered = remembered
        self.store = store
        self.panel = panel
    }

    package func verifyControlAccess() async throws {
        guard NSRunningApplication.running(bundleID) != nil else { throw MusicPlayerError.playerNotRunning }
        guard AccessibilityPermission.isTrusted(prompt: false) else { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    /// Its state isn't read here: the player's other signs tell it.
    package func playerState() async -> PlayerState { .unknown }

    package func pause() async throws { try await press(pausing: true) }

    package func play() async throws { try await press(pausing: false) }

    private func press(pausing: Bool) async throws {
        guard let app = NSRunningApplication.running(bundleID) else { throw MusicPlayerError.playerNotRunning }
        let pid = app.processIdentifier
        let titles = AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).compactMap { $0.string(kAXTitleAttribute) }
        let others = Set(NSWorkspace.shared.runningApplications.compactMap(\.localizedName))
        let holds = pausing && NowPlayingApp.current() == .process(pid)
        let (name, remembered, panel) = (name, remembered, panel)
        let pressed: String? = await queue.run {
            var chosen: String?
            _ = panel.pressRow { rows in
                let row = PanelRows.row(in: rows, pausing: pausing, appName: name, otherApps: others, texts: titles,
                                        remembered: remembered, holdsNowPlaying: holds)
                chosen = row?.text
                return row
            }
            return chosen
        }
        guard let pressed else { throw MusicPlayerError.playerCommandFailed(.pressFailed) }
        if pressed != self.remembered {
            self.remembered = pressed
            setup.ways = setup.ways.map { $0.isPanel ? .panel(rememberedRow: pressed) : $0 }
            // Only while it's still kept: a setup the user removed isn't added back.
            if store.setups().contains(where: { $0.bundleID == bundleID }) { store.save(setup) }
        }
    }

    package func volume() async -> Int? { nil }
    package func setVolume(_ volume: Int) async throws {}

    @MainActor
    package func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { .unknown }, onChange: onChange)
    }

    package nonisolated var stateReportDelay: TimeInterval { PolledStateObserver.reportDelay }
}
