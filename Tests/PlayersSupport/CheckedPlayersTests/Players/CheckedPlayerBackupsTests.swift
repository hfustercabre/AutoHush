import Foundation
import Testing
@testable import CheckedPlayers
import ScriptablePlayers
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

@Suite("CheckedPlayer's backups", .waitsTimeLimit)
struct CheckedPlayerBackupsTests {
    private let app = URL(fileURLWithPath: "/Applications/Jukebox.app")
    private static let refused = MusicPlayerError.playerCommandFailed(.pressIgnored)

    private static func way(_ kind: CheckResult.WayKind) -> PlayerSetup.Way {
        switch kind {
        case .script: .script(ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false))
        case .menu: .menu(menuName: "Controls")
        case .page: .page(.webKit)
        case .panel: .panel(rememberedRow: nil)
        }
    }

    /// It worked in every state of the trip but `failing`.
    private static func result(_ kind: CheckResult.WayKind, failing: [CheckResult.WindowState] = []) -> CheckResult.WayResult {
        CheckResult.WayResult(kind: kind, mark: failing.isEmpty ? .works : .some, failedStates: failing,
                              states: CheckResult.WindowState.trip.map { .init(state: $0, outcome: failing.contains($0) ? .failed : .worked) })
    }

    /// The app, its page chosen (`chosen`, failing in `failing`), backed up
    /// by `backups`, its window in `window` (each look counted in `looks`).
    private func jukebox(_ chosen: MockMusicPlayer, chosenKind: CheckResult.WayKind = .page, failing: [CheckResult.WindowState] = [],
                         backups: [(MockMusicPlayer, CheckResult.WayKind)], signs: [any MusicPlayer] = [],
                         window: CheckResult.WindowState = .visible, looks: Locked<Int> = Locked(0),
                         allowed: @escaping @Sendable (CheckResult.WayKind) -> Bool = { _ in true },
                         audioRecording: Bool = true, usesBackups: Bool = true, panelWhileMuted: Bool = true,
                         clock: Locked<Date> = Locked(Date(timeIntervalSince1970: 0))) -> CheckedPlayer {
        let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: [Self.way(chosenKind)],
                                backups: backups.map { Self.way($0.1) },
                                wayResults: [Self.result(chosenKind, failing: failing)] + backups.map { Self.result($0.1) },
                                usesBackups: usesBackups, panelWhileMuted: panelWhileMuted)
        return CheckedPlayer(setup: setup, parts: .init(ways: [chosen], signs: signs, backups: backups.map { .init(player: $0.0, kind: $0.1) }),
                             reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in }, audioRecordingAllowed: { audioRecording },
                             windowState: { _ in looks.withLock { $0 += 1 }; return window }, backupAllowed: { kind, _ in allowed(kind) },
                             now: { clock.value })
    }

    private func pauses(_ players: MockMusicPlayer...) async -> [Int] {
        var counts: [Int] = []
        for player in players { counts.append(await player.pauseCallCount) }
        return counts
    }

    private func plays(_ players: MockMusicPlayer...) async -> [Int] {
        var counts: [Int] = []
        for player in players { counts.append(await player.playCallCount) }
        return counts
    }

    private func failing(_ state: PlayerState = .playing, pause: Bool = true) async -> MockMusicPlayer {
        let player = MockMusicPlayer(state: state)
        if pause { await player.setFailPause(Self.refused) } else { await player.setFailPlay(Self.refused) }
        return player
    }

    @Test("a pause goes to the first way that worked in the window's state, and to it alone: refused, it's left to AutoHush's mute")
    func firstWayOnly() async throws {
        let page = MockMusicPlayer(state: .playing), menu = MockMusicPlayer(state: .playing), panel = MockMusicPlayer(state: .playing)
        let minimized = jukebox(page, failing: [.minimized], backups: [(menu, .menu), (panel, .panel)], window: .minimized)
        try await minimized.pause()
        #expect(await pauses(page, menu, panel) == [0, 1, 0])
        await menu.setState(.playing)
        await menu.setFailPause(Self.refused)
        await #expect(throws: Self.refused) { try await minimized.pause() }
        #expect(await pauses(menu, panel) == [2, 0])
        // In sight, its page.
        let shown = MockMusicPlayer(state: .playing), other = MockMusicPlayer(state: .playing)
        try await jukebox(shown, failing: [.minimized], backups: [(other, .menu)], window: .visible).pause()
        #expect(await pauses(shown, other) == [1, 0])
    }

    @Test("while it's muted, each retry presses one way, the next in the order after its first press's, the quiet ones round again, the panel once in each pause, and only while its switch is on")
    func whileMuted() async throws {
        let page = await failing(), menu = await failing(), panel = await failing()
        let muted = jukebox(page, backups: [(menu, .menu), (panel, .panel)])
        await #expect(throws: Self.refused) { try await muted.pause() }
        for _ in 1...4 { await #expect(throws: Self.refused) { try await muted.pauseQuietly() } }
        #expect(await pauses(page, menu, panel) == [2, 2, 1]) // the pause, then the menu, the panel, the page, the menu
        // A new pause: the panel again while muted.
        await #expect(throws: Self.refused) { try await muted.pause() }
        for _ in 1...2 { await #expect(throws: Self.refused) { try await muted.pauseQuietly() } }
        #expect(await pauses(page, menu, panel) == [3, 3, 2])

        let shy = await failing(), shyPanel = await failing()
        let off = jukebox(shy, backups: [(shyPanel, .panel)], panelWhileMuted: false)
        await #expect(throws: Self.refused) { try await off.pause() }
        await #expect(throws: Self.refused) { try await off.pauseQuietly() }
        #expect(await pauses(shy, shyPanel) == [2, 0])
    }

    @Test("while it's muted, its retries follow the window's state too: a way that failed there isn't pressed")
    func mutedByWindow() async throws {
        let page = MockMusicPlayer(state: .playing), menu = await failing(), panel = await failing()
        let minimized = jukebox(page, failing: [.minimized], backups: [(menu, .menu), (panel, .panel)], window: .minimized)
        await #expect(throws: Self.refused) { try await minimized.pause() }
        for _ in 1...3 { await #expect(throws: Self.refused) { try await minimized.pauseQuietly() } }
        #expect(await pauses(page, menu, panel) == [0, 3, 1])
    }

    @Test("while it's muted, a chosen panel comes after the quiet ways")
    func chosenPanelWhileMuted() async throws {
        let panel = await failing(), menu = MockMusicPlayer(state: .playing)
        try await jukebox(panel, chosenKind: .panel, backups: [(menu, .menu)]).pauseQuietly()
        #expect(await pauses(panel, menu) == [0, 1])
    }

    @Test("with no mute to stand in (no Audio Recording, AntiDot mode), a refused pause goes down the order at once")
    func noMute() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing)
        try await jukebox(page, backups: [(menu, .menu)], audioRecording: false).pause()
        #expect(await menu.pauseCallCount == 1)
        let antiDotPage = await failing(), antiDotMenu = MockMusicPlayer(state: .playing)
        let antiDot = jukebox(antiDotPage, backups: [(antiDotMenu, .menu)])
        antiDot.allowTaps(false)
        try await antiDot.pause()
        #expect(await antiDotMenu.pauseCallCount == 1)
    }

    @Test("a refused play goes down the order at once; a panel that just failed a play is left out of the next ones for a while")
    func play() async throws {
        let page = await failing(.paused, pause: false), menu = await failing(.paused, pause: false), panel = await failing(.paused, pause: false)
        let clock = Locked(Date(timeIntervalSince1970: 0))
        let paused = jukebox(page, backups: [(menu, .menu), (panel, .panel)], clock: clock)
        await #expect(throws: Self.refused) { try await paused.play() }
        #expect(await plays(page, menu, panel) == [1, 1, 1])
        await #expect(throws: Self.refused) { try await paused.play() } // retried a second later: not the panel
        #expect(await plays(menu, panel) == [2, 1])
        clock.withLock { $0 += CheckedPlayer.panelPlayRest } // Try Again, later
        await #expect(throws: Self.refused) { try await paused.play() }
        #expect(await panel.playCallCount == 2)
    }

    @Test("a pause or play begun meanwhile ends one going down its ways")
    func supersededPlay() async throws {
        let page = await failing(.paused, pause: false), menu = MockMusicPlayer(state: .paused)
        let paused = jukebox(page, backups: [(menu, .menu)])
        await page.setBeforePlay { try? await paused.pause() }
        await #expect(throws: Self.refused) { try await paused.play() }
        #expect(await plays(menu) == [0])
    }

    @Test("a press that took late isn't followed by a backup, which could undo it")
    func tookLate() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing), sign = MockMusicPlayer(state: .paused)
        try await jukebox(page, backups: [(menu, .menu)], signs: [sign], audioRecording: false).pause()
        #expect(await pauses(page, menu) == [1, 0])
    }

    @Test("a way that can't press yet (its page's button not learned) hands the pause on, as if it hadn't been pressed; none able to, it's still learning")
    func stillLearning() async throws {
        let page = MockMusicPlayer(state: .playing), menu = MockMusicPlayer(state: .playing)
        await page.setFailPause(MusicPlayerError.stillLearning)
        try await jukebox(page, backups: [(menu, .menu)]).pause()
        #expect(await pauses(page, menu) == [1, 1])
        let learning = MockMusicPlayer(state: .playing), alsoLearning = MockMusicPlayer(state: .playing)
        await learning.setFailPause(MusicPlayerError.stillLearning)
        await alsoLearning.setFailPause(MusicPlayerError.stillLearning)
        await #expect(throws: MusicPlayerError.stillLearning) { try await jukebox(learning, backups: [(alsoLearning, .menu)]).pause() }
    }

    @Test("a backup macOS would ask something for is passed over")
    func notAllowed() async throws {
        let page = await failing(), script = MockMusicPlayer(state: .playing), menu = MockMusicPlayer(state: .playing)
        try await jukebox(page, backups: [(script, .script), (menu, .menu)], allowed: { $0 != .script }, audioRecording: false).pause()
        #expect(await pauses(script, menu) == [0, 1])
    }

    @Test("its window is looked at only when its state changes the order")
    func looks() async throws {
        let looks = Locked(0)
        try await jukebox(MockMusicPlayer(state: .playing), backups: [(MockMusicPlayer(state: .playing), .menu)], looks: looks).pause()
        #expect(looks.value == 0)
        try await jukebox(MockMusicPlayer(state: .playing), failing: [.hidden], backups: [(MockMusicPlayer(state: .playing), .menu)],
                          looks: looks).pause()
        #expect(looks.value == 1)
    }

    @Test("with its backups off, only its ways are pressed, as before them")
    func backupsOff() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing)
        let off = jukebox(page, backups: [(menu, .menu)], audioRecording: false, usesBackups: false)
        await #expect(throws: Self.refused) { try await off.pause() }
        await #expect(throws: Self.refused) { try await off.pauseQuietly() }
        #expect(await menu.pauseCallCount == 0)
    }

    @Test("its page mutes it itself only with no backups in use, and never a Chromium web app's")
    func pageMute() {
        #expect(CheckedPlayer.pageMutesItself(.webKit, backups: []))
        #expect(!CheckedPlayer.pageMutesItself(.webKit, backups: [.panel(rememberedRow: nil)]))
        #expect(!CheckedPlayer.pageMutesItself(PageAccess(interface: .chromiumWebApp(browserID: "com.google.Chrome"), switchAttribute: nil), backups: []))
    }
}
