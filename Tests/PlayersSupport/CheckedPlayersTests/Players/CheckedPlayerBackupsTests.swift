import Foundation
import os
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
    /// by `backups`, then by the Play/Pause key (`key`), its window in
    /// `window` (each look counted in `looks`).
    private func jukebox(_ chosen: MockMusicPlayer, chosenKind: CheckResult.WayKind = .page, failing: [CheckResult.WindowState] = [],
                         backups: [(MockMusicPlayer, CheckResult.WayKind)], key: MockMusicPlayer? = nil, signs: [any MusicPlayer] = [],
                         window: CheckResult.WindowState = .visible, looks: Locked<Int> = Locked(0),
                         allowed: @escaping @Sendable (WayOrder.Kind) -> Bool = { _ in true },
                         audioRecording: Bool = true, usesBackups: Bool = true, panelWhileMuted: Bool = true,
                         clock: Locked<Date> = Locked(Date(timeIntervalSince1970: 0))) -> CheckedPlayer {
        let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: [Self.way(chosenKind)],
                                backups: backups.map { Self.way($0.1) },
                                wayResults: [Self.result(chosenKind, failing: failing)] + backups.map { Self.result($0.1) },
                                usesBackups: usesBackups, panelWhileMuted: panelWhileMuted)
        let kept = backups.map { CheckedPlayer.Backup(player: $0.0, kind: WayOrder.Kind($0.1)) } + (key.map { [.init(player: $0, kind: .mediaKey)] } ?? [])
        return CheckedPlayer(setup: setup, parts: .init(ways: [chosen], signs: signs, backups: kept),
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

    @Test("the control that paused and played it last is kept, a backup's too; with its backups off, its own way's")
    func lastUsed() async throws {
        let page = MockMusicPlayer(state: .playing), menu = MockMusicPlayer(state: .playing)
        let minimized = jukebox(page, failing: [.minimized], backups: [(menu, .menu)], window: .minimized)
        try await minimized.pause()
        #expect(minimized.controls.last == LastControls(paused: .menu))
        let own = MockMusicPlayer(state: .playing)
        let off = jukebox(own, backups: [(MockMusicPlayer(state: .playing), .menu)], usesBackups: false)
        try await off.pause()
        try await off.play()
        #expect(off.controls.last == LastControls(paused: .page, played: .page))
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

    @Test("while it's muted, the Play/Pause key is tried once in each pause, after the quiet ways and before the panel")
    func keyWhileMuted() async throws {
        let page = await failing(), menu = await failing(), key = await failing(), panel = await failing()
        let muted = jukebox(page, backups: [(menu, .menu), (panel, .panel)], key: key)
        await #expect(throws: Self.refused) { try await muted.pause() }
        for _ in 1...5 { await #expect(throws: Self.refused) { try await muted.pauseQuietly() } }
        #expect(await pauses(page, menu, key, panel) == [2, 2, 1, 1]) // the pause, then the menu, the key, the panel, the page, the menu
        // Its switch off, the panel isn't tried, the key still is, once.
        let shy = await failing(), shyKey = await failing(), shyPanel = await failing()
        let off = jukebox(shy, backups: [(shyPanel, .panel)], key: shyKey, panelWhileMuted: false)
        await #expect(throws: Self.refused) { try await off.pause() }
        for _ in 1...3 { await #expect(throws: Self.refused) { try await off.pauseQuietly() } }
        #expect(await pauses(shy, shyKey, shyPanel) == [3, 1, 0])
    }

    @Test("a Play/Pause key that isn't pressed (another app is Now Playing) hands the pause on, as one passed over, and while muted, the same retry")
    func keyNotPressed() async throws {
        let page = MockMusicPlayer(state: .playing), key = MockMusicPlayer(state: .playing), panel = MockMusicPlayer(state: .playing)
        await key.setFailPause(MediaKeyWay.NotPressed(description: "another app is Now Playing"))
        try await jukebox(page, failing: [.minimized], backups: [(panel, .panel)], key: key, window: .minimized, panelWhileMuted: false).pause()
        #expect(await pauses(page, key, panel) == [0, 1, 1])
        // Muted, its quiet way refused: the key passes, then the panel, in one retry.
        let refusing = await failing(), mutedKey = MockMusicPlayer(state: .playing), mutedPanel = MockMusicPlayer(state: .playing)
        await mutedKey.setFailPause(MediaKeyWay.NotPressed(description: "no app is Now Playing"))
        let muted = jukebox(refusing, backups: [(mutedPanel, .panel)], key: mutedKey)
        await #expect(throws: Self.refused) { try await muted.pause() }
        try await muted.pauseQuietly()
        #expect(await pauses(refusing, mutedKey, mutedPanel) == [1, 1, 1])
        // Declined at the first press, it isn't asked again in that pause.
        let shy = MockMusicPlayer(state: .playing), declining = MockMusicPlayer(state: .playing), refusingPanel = await failing()
        await declining.setFailPause(MediaKeyWay.NotPressed(description: "another app is Now Playing"))
        let once = jukebox(shy, failing: [.minimized], backups: [(refusingPanel, .panel)], key: declining, window: .minimized)
        await #expect(throws: Self.refused) { try await once.pause() }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressFailed)) { try await once.pauseQuietly() }
        #expect(await pauses(shy, declining, refusingPanel) == [0, 1, 1])
    }

    @Test("a refused play goes to the Play/Pause key after the other ways, before the panel")
    func keyPlay() async throws {
        let page = await failing(.paused, pause: false), menu = await failing(.paused, pause: false)
        let key = MockMusicPlayer(state: .paused), panel = MockMusicPlayer(state: .paused)
        try await jukebox(page, backups: [(menu, .menu), (panel, .panel)], key: key).play()
        #expect(await plays(page, menu, key, panel) == [1, 1, 1, 0])
    }

    @Test("a muted retry whose ways are all passed over goes round once more, so it presses its own way; a page still learning hands on")
    func mutedNothingPressed() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing)
        let muted = jukebox(page, backups: [(menu, .menu)], allowed: { _ in false })
        await #expect(throws: Self.refused) { try await muted.pause() }
        await #expect(throws: Self.refused) { try await muted.pauseQuietly() }
        #expect(await pauses(page, menu) == [2, 0])
        let refusing = await failing(), learning = MockMusicPlayer(state: .playing), panel = MockMusicPlayer(state: .playing)
        await learning.setFailPause(MusicPlayerError.stillLearning)
        let handsOn = jukebox(refusing, backups: [(learning, .page), (panel, .panel)])
        await #expect(throws: Self.refused) { try await handsOn.pause() }
        try await handsOn.pauseQuietly()
        #expect(await pauses(learning, panel) == [1, 1])
    }

    @Test("a pause no mute will stand in for goes down its backups at once")
    func uncovered() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing)
        try await jukebox(page, backups: [(menu, .menu)]).pauseUncovered()
        #expect(await menu.pauseCallCount == 1)
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

    @Test("its chosen way's permission missing, its backups control it if one can be pressed without macOS asking: each press passes over it until macOS allows it again")
    func chosenPermissionMissing() async throws {
        let allowed = Locked<Set<WayOrder.Kind>>([.menu])
        let script = MockMusicPlayer(state: .playing, failVerifyWith: MusicPlayerError.automationPermissionDenied)
        let menu = MockMusicPlayer(state: .playing)
        let player = jukebox(script, chosenKind: .script, backups: [(menu, .menu)], allowed: { allowed.value.contains($0) })
        try await player.verifyControlAccess()
        try await player.pause()
        try await player.pauseQuietly()
        try await player.play()
        #expect(await pauses(script, menu) == [0, 2])
        #expect(await plays(script, menu) == [0, 1])
        // Its menu refusing, muted: its retry by the menu again, never its script.
        await menu.setFailPause(Self.refused)
        await #expect(throws: Self.refused) { try await player.pause() }
        await menu.setFailPause(nil)
        try await player.pauseQuietly()
        #expect(await pauses(script, menu) == [0, 4])
        // No backup allowed either: nothing pressed, its own permission missing.
        allowed.value = []
        await #expect(throws: MusicPlayerError.automationPermissionDenied) { try await player.pauseUncovered() }
        // Allowed again: its script, checked at the press without asking, and its access too.
        allowed.value = [.script, .menu]
        await script.setFailVerify(nil)
        try await player.pause()
        #expect(await pauses(script, menu) == [1, 4])
        try await player.verifyControlAccess()
    }

    @Test("its chosen way's permission missing, it can't be controlled as before when no backup can be pressed without macOS asking, or its backups are off")
    func chosenPermissionMissingNoBackup() async throws {
        let page = MockMusicPlayer(state: .playing, failVerifyWith: MusicPlayerError.accessibilityPermissionDenied)
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) {
            try await jukebox(page, backups: [(MockMusicPlayer(), .menu)], allowed: { _ in false }).verifyControlAccess()
        }
        await #expect(throws: MusicPlayerError.accessibilityPermissionDenied) {
            try await jukebox(page, backups: [(MockMusicPlayer(), .script)], usesBackups: false).verifyControlAccess()
        }
        // A backup by its AppleScript, already allowed: controlled by it.
        let script = MockMusicPlayer(state: .playing)
        let backedUp = jukebox(page, backups: [(script, .script)], allowed: { $0 == .script })
        try await backedUp.verifyControlAccess()
        try await backedUp.pause()
        #expect(await pauses(page, script) == [0, 1])
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
        #expect(CheckedPlayer.pageMutesItself(.webKit, backedUp: false))
        #expect(!CheckedPlayer.pageMutesItself(.webKit, backedUp: true))
        #expect(!CheckedPlayer.pageMutesItself(PageAccess(interface: .chromiumWebApp(browserID: "com.google.Chrome"), switchAttribute: nil), backedUp: false))
    }

    @Test("its page's mute follows the backup switch as it is now: backups (the Play/Pause key alone counts) in use mean AutoHush's mute")
    func pageMuteFollowsSwitch() async throws {
        func page(_ setup: PlayerSetup) -> SafariWebAppPlayer? {
            let switches = OSAllocatedUnfairLock(initialState: setup.switches)
            let parts = CheckedPlayer.parts(for: setup, store: MemorySetupStore(), switches: switches)
            switches.withLock { $0.usesBackups = false }
            let off = parts.page?.control.mutesRefusals()
            switches.withLock { $0.usesBackups = true }
            #expect(off == true && parts.page?.control.mutesRefusals() == false)
            return parts.page
        }
        let checked = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: [.page(.webKit)],
                                  wayResults: [Self.result(.page)]) // the key alone
        #expect(page(checked) != nil)
        var older = checked
        older.wayResults = [] // no backup at all: it mutes itself, switch or not
        let parts = CheckedPlayer.parts(for: older, store: MemorySetupStore())
        #expect(parts.page?.control.mutesRefusals() == true)
    }

    @Test("its switches change at once, with no new player: off, its own way alone; on again, its backups")
    func switchesLive() async throws {
        let page = await failing(), menu = MockMusicPlayer(state: .playing)
        let player = jukebox(page, backups: [(menu, .menu)], audioRecording: false)
        player.setSwitches(BackupSwitches(usesBackups: false))
        #expect(!player.usesBackups && !player.controls.switches.usesBackups && !player.setupNow.usesBackups)
        await #expect(throws: Self.refused) { try await player.pause() }
        #expect(await menu.pauseCallCount == 0)
        // A press by its own way alone is a press begun all the same.
        #expect(await player.pressCalls == 1)
        #expect(await player.mutedTried.isEmpty)
        player.setSwitches(BackupSwitches())
        try await player.pause()
        #expect(await menu.pauseCallCount == 1)
    }

    @Test("its permission is its chosen way's, or the main control's while that one is pressed alone (its backups off)")
    func permission() {
        let player = jukebox(MockMusicPlayer(state: .playing), backups: [(MockMusicPlayer(state: .playing), .script)])
        #expect(player.controlPermission == .accessibility(player: "Jukebox")) // its page
        player.setSwitches(BackupSwitches(usesBackups: false, mainControl: "script"))
        #expect(player.controlPermission == .automation(player: "Jukebox"))
        player.setSwitches(BackupSwitches(mainControl: "script")) // backups on: its page checked first, as before
        #expect(player.controlPermission == .accessibility(player: "Jukebox"))
    }

    @Test("a backup page mutes nothing new while its backups are off")
    func backupPageOff() async {
        let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: [.menu(menuName: "Controls")],
                                backups: [.page(.webKit)], wayResults: [Self.result(.menu), Self.result(.page)], usesBackups: false)
        let player = CheckedPlayer(setup: setup, reports: nil, store: MemorySetupStore())
        #expect(player.parts.pageIsBackup && player.parts.page != nil)
        #expect(await !player.muteIfPlayingAnyway())
    }
}
