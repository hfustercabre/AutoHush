import AppKit
import Foundation
import AutoHushKit

/// Pausing and playing an app through its row in the menu bar's Now Playing
/// panel: the last way (the user, 2026-10-15), since the panel shows on
/// screen for about half a second and takes the keyboard. Its row is the one
/// showing what the app plays (its windows' titles) or its name, else the
/// row it changed with last (kept in its setup), else, pausing, the only one
/// playing while it holds Now Playing. Its state comes from its other signs.
package actor PanelWay: MusicPlayer {
    /// What tells the app's row, read just before the panel opens: its
    /// windows' titles, the other running apps' names, and whether it holds
    /// Now Playing.
    package struct Shown: Sendable {
        package var titles: [String]
        package var otherApps: Set<String>
        package var holdsNowPlaying: Bool

        package init(titles: [String], otherApps: Set<String>, holdsNowPlaying: Bool) {
            self.titles = titles
            self.otherApps = otherApps
            self.holdsNowPlaying = holdsNowPlaying
        }
    }

    package nonisolated let bundleID: String
    package nonisolated let name: String
    package nonisolated var controlPermission: Permission { .accessibility(player: name) }
    package nonisolated var canFade: Bool { false }
    private var remembered: String?
    private let store: any PlayerSetupStore
    private let panel: any NowPlayingPanel
    private let processIdentifier: @Sendable () -> pid_t?
    private let shown: @Sendable (pid_t) -> Shown
    private let queue = DispatchQueue(label: "AutoHush.NowPlayingPanel", qos: .userInitiated)

    /// `panel`, `processIdentifier` and `shown`: the real ones; tests stand in for them.
    package init(setup: PlayerSetup, remembered: String?, store: any PlayerSetupStore,
                 panel: any NowPlayingPanel = AccessibilityNowPlayingPanel(),
                 processIdentifier: (@Sendable () -> pid_t?)? = nil,
                 shown: @escaping @Sendable (pid_t) -> Shown = PanelWay.shown) {
        bundleID = setup.bundleID
        name = setup.name
        self.remembered = remembered
        self.store = store
        self.panel = panel
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.shown = shown
    }

    /// What the app shows now, through Accessibility and NSWorkspace.
    package static let shown: @Sendable (pid_t) -> Shown = { pid in
        let titles = AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).compactMap { $0.string(kAXTitleAttribute) }
        let others = Set(NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != pid }.compactMap(\.localizedName))
        return Shown(titles: titles, otherApps: others, holdsNowPlaying: NowPlayingApp.current() == .process(pid))
    }

    package func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
        guard AccessibilityPermission.isTrusted(prompt: false) else { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    /// Its state isn't read here: the player's other signs tell it.
    package func playerState() async -> PlayerState { .unknown }

    package func pause() async throws { try await press(pausing: true) }

    package func play() async throws { try await press(pausing: false) }

    private func press(pausing: Bool) async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        let (name, remembered, panel, shown) = (name, remembered, panel, shown)
        let (pressed, hidden): (String?, Bool) = await queue.run {
            // Read before the panel opens (Now Playing is asked of a fresh process).
            let now = shown(pid)
            var chosen: String?
            let opened = panel.pressRow { rows in
                let row = PanelRows.row(in: rows, pausing: pausing, appName: name, otherApps: now.otherApps, texts: now.titles,
                                        remembered: remembered, holdsNowPlaying: pausing && now.holdsNowPlaying)
                chosen = row?.text
                return row
            }
            // Not opened: hidden in the menu bar, which the user can change.
            return (chosen, opened == nil && !panel.isInMenuBar())
        }
        guard let pressed else { throw MusicPlayerError.playerCommandFailed(hidden ? .nowPlayingHidden : .pressFailed) }
        guard pressed != self.remembered else { return }
        self.remembered = pressed
        // Only its row changes, in the setup kept now (checked again since, it
        // may have other ways), and only while it's kept: a setup the user
        // removed isn't added back.
        store.update(bundleID) { setup in
            guard setup.ways.contains(where: \.isPanel) else { return }
            setup.ways = setup.ways.map { $0.isPanel ? .panel(rememberedRow: pressed) : $0 }
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
