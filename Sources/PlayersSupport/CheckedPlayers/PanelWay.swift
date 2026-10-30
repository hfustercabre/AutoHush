import AppKit
import Foundation
import AutoHushKit
import ScriptablePlayers

/// Pausing and playing an app through its row in the menu bar's Now Playing
/// panel: the last way (the user, 2026-10-15), since the panel shows on
/// screen for about half a second and takes the keyboard. Its row is the one
/// showing what the app plays or its name, else the row it changed with last
/// (kept in its setup), else, pausing, the only one playing while it holds
/// Now Playing, as its check told it (`PanelRows.row`). What it plays shows
/// in its windows' titles and, where its check found them (`PanelClues`),
/// what it plays by AppleScript and its page's player bar; the bar is read
/// only when nothing else told its row, as the check reads it (a page can
/// take a second), and the panel opened again. Its state comes from its
/// other signs; for a row that doesn't follow the app
/// (`PlayerSetup.panelRowIsStale`), from its sound, and the row is pressed
/// as a toggle, only when its sound says it isn't as wanted yet, then
/// checked here by its sound.
actor PanelWay: MusicPlayer {
    /// What tells the app's row, read just before the panel opens: its
    /// windows' titles, what it plays by AppleScript, the other running
    /// apps' names, and whether it holds Now Playing; its page's player bar,
    /// later, when those don't tell.
    struct Shown: Sendable {
        var titles: [String]
        /// What it plays, by AppleScript (`PanelClues.script`).
        var track: String?
        /// Its page's player bar's texts (`PanelClues.page`).
        var bar: [String]
        var otherApps: Set<String>
        var holdsNowPlaying: Bool

        init(titles: [String], track: String? = nil, bar: [String] = [], otherApps: Set<String>, holdsNowPlaying: Bool) {
            self.titles = titles
            self.track = track
            self.bar = bar
            self.otherApps = otherApps
            self.holdsNowPlaying = holdsNowPlaying
        }

        /// Each text its song may show in.
        var texts: [String] { titles + (track.map { [$0] } ?? []) + bar }
    }

    nonisolated let bundleID: String
    nonisolated let name: String
    nonisolated var controlPermission: Permission { .accessibility(player: name) }
    nonisolated var canFade: Bool { false }
    /// A row pressed as a toggle is checked here, by the app's sound, and
    /// never pressed again: a second press would undo a first the app is
    /// only slow to show (Qobuz buffering). Any other row's press is checked
    /// by the player's other signs.
    nonisolated var checksItsPresses: Bool { rowIsStale }
    private var remembered: String?
    private let store: any PlayerSetupStore
    private let panel: any NowPlayingPanel
    private let processIdentifier: @Sendable () -> pid_t?
    private let shown: @Sendable (pid_t) -> Shown
    /// Its page's player bar's texts, where its check found its song there.
    private let playerBar: (@Sendable (pid_t) -> [String])?
    /// Its row doesn't follow it: its sound tells (`hearing`).
    private nonisolated let rowIsStale: Bool
    private let hearing: LateHearing?
    private let sleep: VolumeFader.Sleep
    private let queue = DispatchQueue(label: "AutoHush.NowPlayingPanel", qos: .userInitiated)

    /// `panel`, `processIdentifier`, `shown` and `sleep` (while a toggle is
    /// checked): the real ones by default, `shown` reading what the setup's
    /// clues say; tests stand in for them. `playerBar` reads its page's
    /// player bar, where its check found its song there (`PanelClues.page`).
    init(setup: PlayerSetup, remembered: String?, store: any PlayerSetupStore,
         panel: any NowPlayingPanel = AccessibilityNowPlayingPanel(),
         processIdentifier: (@Sendable () -> pid_t?)? = nil,
         shown: (@Sendable (pid_t) -> Shown)? = nil, playerBar: (@Sendable (pid_t) -> [String])? = nil,
         hearing: LateHearing? = nil,
         sleep: @escaping VolumeFader.Sleep = { try? await Task.sleep(for: .seconds($0)) }) {
        bundleID = setup.bundleID
        rowIsStale = setup.panelRowIsStale == true
        self.hearing = hearing
        name = setup.name
        self.remembered = remembered
        self.store = store
        self.panel = panel
        self.processIdentifier = processIdentifier ?? { [bundleID = setup.bundleID] in
            NSRunningApplication.running(bundleID)?.processIdentifier
        }
        self.shown = shown ?? Self.shown(song: setup.panelClues?.script)
        self.playerBar = playerBar
        self.sleep = sleep
    }

    /// How long each read of the app's windows waits for it (macOS's 6 s
    /// otherwise), as a menu's and a page's do.
    static let timeout: Float = 0.5

    /// What the app shows now, through Accessibility and NSWorkspace, and
    /// what it plays by AppleScript (`song`), where its check found it says.
    static func shown(song: ScriptedSong?) -> @Sendable (pid_t) -> Shown {
        { pid in
            let titles = AXUIElement.application(pid, timeout: timeout).elements(kAXWindowsAttribute, timeout: timeout)
                .compactMap { $0.string(kAXTitleAttribute) }
            let others = Set(NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != pid }.compactMap(\.localizedName))
            return Shown(titles: titles, track: song?.read(pid: pid), otherApps: others, holdsNowPlaying: NowPlayingApp.current() == .process(pid))
        }
    }

    func verifyControlAccess() async throws {
        guard processIdentifier() != nil else { throw MusicPlayerError.playerNotRunning }
        guard AccessibilityPermission.isTrusted(prompt: false) else { throw MusicPlayerError.accessibilityPermissionDenied }
    }

    /// Its state isn't read here: the player's other signs tell it.
    func playerState() async -> PlayerState { .unknown }

    func pause() async throws { try await press(pausing: true) }

    func play() async throws { try await press(pausing: false) }

    private func press(pausing: Bool) async throws {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        guard rowIsStale else { return try await pressRow(pid: pid, pausing: pausing) }
        // Its row doesn't follow it: its sound tells how it is, the row is
        // pressed as a toggle only when that isn't as wanted yet, and the
        // press is given `PressCheck.toggleWait` to be heard, never made twice.
        let hearing = hearing
        let heard: @Sendable () async -> PlayerState = { await hearing?.heard(pid).map { $0 ? .playing : .paused } ?? .unknown }
        let before = await heard()
        guard before != .unknown else { throw MusicPlayerError.playerCommandFailed(.hearingUnavailable) }
        guard (before == .playing) == pausing else { return }
        try await PressCheck(name: name, isToggle: true, press: { [self] _ in try await pressRow(pid: pid, pausing: pausing) },
                             state: heard, sleep: sleep).press(to: pausing ? .paused : .playing)
    }

    /// Presses its row's Play/Pause, and keeps the row in its setup.
    private func pressRow(pid: pid_t, pausing: Bool) async throws {
        let (name, remembered, panel, shown, playerBar, asToggle) = (name, remembered, panel, shown, playerBar, rowIsStale)
        let (pressed, hidden): (String?, Bool) = await queue.run {
            // Read before the panel opens (Now Playing is asked of a fresh process).
            var now = shown(pid)
            var chosen: String?, declined = false
            /// Its row (`PanelRows.row`); `told`: only one its song, its name
            /// or memory tells (its player bar is still to be read).
            func pick(_ rows: [PanelRow], told: Bool) -> PanelRow? {
                guard let row = PanelRows.row(in: rows, pausing: pausing, appName: name, otherApps: now.otherApps, texts: now.texts,
                                              remembered: remembered, holdsNowPlaying: pausing && now.holdsNowPlaying, asToggle: asToggle)
                else { return nil }
                // Remembered without its times (`withoutTimes`), as the row is compared.
                guard !told || remembered.map({ PanelRows.withoutTimes(row.text) == PanelRows.withoutTimes($0) }) == true
                        || !PanelRows.appRows([row], appName: name, otherApps: now.otherApps, texts: now.texts).isEmpty else {
                    declined = true
                    return nil
                }
                chosen = row.text
                return row
            }
            var opened = panel.pressRow { pick($0, told: playerBar != nil) }
            // Nothing it shows told its row: its page's player bar may, as
            // its check found, read now (with the panel closed) and the
            // panel opened again.
            if opened == false, chosen == nil, let playerBar {
                now.bar = playerBar(pid)
                if declined || !now.bar.isEmpty { opened = panel.pressRow { pick($0, told: false) } }
            }
            // Not opened: hidden in the menu bar, which the user can change.
            // A row chosen counts only once its press took.
            return (opened == true ? chosen : nil, opened == nil && !panel.isInMenuBar())
        }
        guard let pressed else { throw MusicPlayerError.playerCommandFailed(hidden ? .nowPlayingHidden : .pressFailed) }
        // Kept without its times, which change as it plays (`withoutTimes`).
        let kept = PanelRows.withoutTimes(pressed)
        guard kept != self.remembered else { return }
        self.remembered = kept
        // Only its row changes, in the setup kept now (checked again since, it
        // may have other ways), and only while it's kept: a setup the user
        // removed isn't added back.
        store.update(bundleID) { setup in
            guard setup.ways.contains(where: \.isPanel) else { return }
            setup.ways = setup.ways.map { $0.isPanel ? .panel(rememberedRow: kept) : $0 }
        }
    }

    func volume() async -> Int? { nil }
    func setVolume(_ volume: Int) async throws {}

    @MainActor
    func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
        PolledStateObserver(read: { .unknown }, onChange: onChange)
    }

    nonisolated var stateReportDelay: TimeInterval { PolledStateObserver.reportDelay }
}
