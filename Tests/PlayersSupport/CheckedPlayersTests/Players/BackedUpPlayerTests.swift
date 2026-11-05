import Foundation
import Testing
@testable import CheckedPlayers
import ScriptablePlayers
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

@Suite("BackedUpPlayer", .waitsTimeLimit)
struct BackedUpPlayerTests {
    private static let refused = MusicPlayerError.playerCommandFailed(.pressIgnored)

    /// `inner` backed up by `backups`, untested by window state, its
    /// switches in `switches`.
    private func backed<Inner: MusicPlayer>(_ inner: Inner, _ backups: [(MockMusicPlayer, WayOrder.Kind)],
                                            switches: Locked<BackupSwitches> = Locked(BackupSwitches()),
                                            audioRecording: Bool = true) -> BackedUpPlayer<Inner> {
        BackedUpPlayer(inner: inner, own: CheckResult.WayResult(kind: .script, mark: .works),
                       backups: backups.map { CheckedPlayer.Backup(player: $0.0, kind: $0.1) }, results: backups.map { _ in nil },
                       switches: { switches.value }, processIdentifier: { 4242 }, windowState: { _ in .visible },
                       backupAllowed: { _, _ in true }, audioRecordingAllowed: { audioRecording }, pressSleep: { _ in })
    }

    /// A backup that takes: it checks its own press, since its stand-in isn't the app `inner` reads.
    private func taking(_ state: PlayerState = .playing) -> MockMusicPlayer {
        MockMusicPlayer(state: state, checksItsPresses: true)
    }

    private func failing(_ state: PlayerState = .playing, pause: Bool = true) async -> MockMusicPlayer {
        let player = MockMusicPlayer(state: state)
        if pause { await player.setFailPause(Self.refused) } else { await player.setFailPlay(Self.refused) }
        return player
    }

    private func pauses(_ players: MockMusicPlayer...) async -> [Int] {
        var counts: [Int] = []
        for player in players { counts.append(await player.pauseCallCount) }
        return counts
    }

    @Test("everything but its presses is its own player's")
    func forwards() async throws {
        let inner = MockMusicPlayer(bundleID: "com.example.jukebox", name: "Jukebox", state: .paused, canFade: false,
                                    stateReportDelay: 1, kind: .safariWebApp, releasesOnQuit: true, checksItsPresses: true)
        let player = backed(inner, [(MockMusicPlayer(), .panel)])
        #expect(player.bundleID == "com.example.jukebox" && player.name == "Jukebox" && player.kind == .safariWebApp)
        #expect(!player.canFade && player.stateReportDelay == 1 && player.releasesOnQuit && !player.isUntested)
        #expect(await player.playerState() == .paused)
        try await player.verifyControlAccess()
        #expect(await inner.verifyCallCount == 1)
    }

    @Test("its volume, release and mute calls go to its own player, and a web app's learning calls too")
    func forwardsCalls() async throws {
        let own = MockMusicPlayer()
        let muting = MockMutingMusicPlayer(own)
        let player = backed(muting, [(MockMusicPlayer(), .panel)])
        try await player.setVolume(40)
        #expect(await player.volume() == 40)
        await player.forgetPause()
        await player.releaseMute()
        #expect(await muting.releasedMutes == 1)
        let plain = MockMusicPlayer()
        await backed(plain, [(MockMusicPlayer(), .panel)]).release()
        #expect(await plain.releases == 1)
        #expect(await own.commandLog.contains("forgetPause"))
        // A learned web app learns again, then keeps what it learned.
        let app = SafariWebApp(bundleID: "com.apple.Safari.WebApp.TEST", name: "Jukebox", url: URL(fileURLWithPath: "/tmp/Jukebox.app"))
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [FollowingPage.place])
        let web = BackedUpPlayer.webApp(SafariWebAppPlayer(app: app, store: MemoryRecipeStore([app.bundleID: recipe])),
                                        switches: BackupSwitchesStore(defaults: MemoryDefaults()))
        await web.learnAgain()
        #expect(web.learningStatus == .relearning)
        await web.keepLearned()
        #expect(web.learningStatus == .learned)
    }

    @Test("a pause goes to its own way only; refused, it's left to AutoHush's mute, whose retries try the Play/Pause key once, then the panel once")
    func pauseThenMuted() async throws {
        let own = await failing(), key = await failing(), panel = taking()
        let player = backed(own, [(key, .mediaKey), (panel, .panel)])
        await #expect(throws: Self.refused) { try await player.pause() }
        #expect(await pauses(own, key, panel) == [1, 0, 0])
        await #expect(throws: Self.refused) { try await player.pauseQuietly() }
        try await player.pauseQuietly()
        #expect(await pauses(own, key, panel) == [1, 1, 1])
    }

    @Test("a play its own player refuses as having nothing to play (QuickTime Player plays only what it paused) isn't made by a backup")
    func nothingToPlay() async throws {
        let own = MockMusicPlayer(state: .paused), key = taking(.paused)
        await own.setFailPlay(MusicPlayerError.playerCommandFailed(.nothingToPlay))
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try await backed(own, [(key, .mediaKey)]).play() }
        #expect(await key.playCallCount == 0)
    }

    @Test("a pause no mute will stand in for goes down its backups at once, its own player's own when they're off")
    func uncovered() async throws {
        let own = await failing(), key = taking()
        try await backed(own, [(key, .mediaKey)]).pauseUncovered()
        #expect(await key.pauseCallCount == 1)
        let plain = MockMusicPlayer()
        try await backed(plain, [(taking(), .mediaKey)], switches: Locked(BackupSwitches(usesBackups: false))).pauseUncovered()
        #expect(await plain.uncoveredPauses == 1)
    }

    @Test("a web app not learned yet uses no backups, as before them: its pause says it's still learning")
    func unlearnedWebApp() async throws {
        let app = SafariWebApp(bundleID: "com.apple.Safari.WebApp.TEST", name: "Jukebox", url: URL(fileURLWithPath: "/tmp/Jukebox.app"))
        let web = SafariWebAppPlayer(app: app, page: FollowingPage(playing: Locked(true)), store: MemoryRecipeStore(),
                                     levelProbe: FakeLevelProbe(audible: true), processIdentifier: { 4242 }, audioRecordingAllowed: { true })
        let key = taking()
        let player = backed(web, [(key, .mediaKey)])
        await #expect(throws: MusicPlayerError.stillLearning) { try await player.pause() }
        #expect(await key.pauseCallCount == 0)
    }

    @Test("with the panel's switch off, it isn't pressed while muted: its own way is, again")
    func panelSwitchOff() async throws {
        let own = await failing(), panel = taking()
        let player = backed(own, [(panel, .panel)], switches: Locked(BackupSwitches(panelWhileMuted: false)))
        await #expect(throws: Self.refused) { try await player.pause() }
        await #expect(throws: Self.refused) { try await player.pauseQuietly() }
        #expect(await pauses(own, panel) == [2, 0])
    }

    @Test("a refused play goes down its backups at once")
    func play() async throws {
        let own = await failing(.paused, pause: false), key = taking(.paused)
        try await backed(own, [(key, .mediaKey)]).play()
        #expect(await own.playCallCount == 1)
        #expect(await key.playCallCount == 1)
    }

    @Test("with its backups off, only its own player is pressed, and its presses are checked as its own player's are")
    func backupsOff() async throws {
        let switches = Locked(BackupSwitches(usesBackups: false))
        let own = await failing(), key = MockMusicPlayer(state: .playing)
        let player = backed(own, [(key, .mediaKey)], switches: switches)
        #expect(!player.checksItsPresses)
        await #expect(throws: Self.refused) { try await player.pause() }
        await #expect(throws: Self.refused) { try await player.pauseQuietly() }
        #expect(await key.pauseCallCount == 0)
        // Turned on, it checks them itself, each way's.
        switches.value = BackupSwitches()
        #expect(player.checksItsPresses)
        #expect(!backed(MockMusicPlayer(), []).checksItsPresses) // none to back it up
    }

    @Test("in AntiDot mode, which can't mute it, a refused pause goes to its backups at once, and its own player is told too")
    func antiDot() async throws {
        let own = await failing(), key = taking()
        let muting = MockMutingMusicPlayer(own)
        let player = backed(muting, [(key, .mediaKey)])
        player.allowTaps(false)
        #expect(!muting.tapsAreAllowed)
        try await player.pause()
        #expect(await key.pauseCallCount == 1)
        // Nor without Audio Recording.
        let other = await failing(), otherKey = taking()
        try await backed(other, [(otherKey, .mediaKey)], audioRecording: false).pause()
        #expect(await otherKey.pauseCallCount == 1)
    }

    @Test("its page, not learned yet, learns its Play/Pause as AutoHush pauses it its own way, and is released with it")
    func pageLearnedByItself() async throws {
        let own = MockMusicPlayer(state: .playing), page = FollowingPage(playing: own.plays)
        let app = SafariWebApp(bundleID: TestPlayer.bundleID, name: "Jukebox", url: URL(fileURLWithPath: "/Applications/Jukebox.app"))
        let learning = SafariWebAppPlayer(app: app, kind: .app, page: page, canMute: false, mutesRefusals: { false }, store: MemoryRecipeStore(),
                                          levelProbe: FakeLevelProbe(audible: true), processIdentifier: { 4242 }, audioRecordingAllowed: { true })
        let player = BackedUpPlayer(inner: own, own: CheckResult.WayResult(kind: .script, mark: .works),
                                    backups: [CheckedPlayer.Backup(player: learning, kind: .page)], results: [nil], learningPage: learning,
                                    switches: { BackupSwitches() }, processIdentifier: { 4242 }, windowState: { _ in .visible },
                                    backupAllowed: { _, _ in true }, pressSleep: { _ in })
        #expect(!learning.learningStatus.isLearned)
        // Out of sight, its page goes by its own player's state.
        #expect(await learning.otherSigns.state() == .playing)
        try await player.pause()
        #expect(learning.learningStatus.isLearned && page.presses == 0)
        // Learned, its switch is turned on as it's started, paused and played.
        let shown = page.shows
        try await player.verifyControlAccess()
        try await player.play()
        try await player.pause()
        #expect(page.shows == shown + 3)
        #expect(player.releasesOnQuit)
        await player.release()
        #expect(page.releases == 1)
    }

    @Test("a web app keeps learning and muting through it, any other player doesn't become one")
    func conformances() {
        let app = SafariWebApp(bundleID: "com.apple.Safari.WebApp.TEST", name: "Jukebox", url: URL(fileURLWithPath: "/tmp/Jukebox.app"))
        let web: any MusicPlayer = BackedUpPlayer.webApp(SafariWebAppPlayer(app: app, store: MemoryRecipeStore()), switches: BackupSwitchesStore(defaults: MemoryDefaults()))
        #expect(web is any LearningMusicPlayer && web is any MutingMusicPlayer && web is any TapsAllowingPlayer)
        let plain: any MusicPlayer = backed(MockMusicPlayer(), [])
        #expect(!(plain is any LearningMusicPlayer) && !(plain is any MutingMusicPlayer))
        #expect((web as? BackedUpPlayer<SafariWebAppPlayer>)?.backups.map(\.kind) == [.mediaKey, .panel])
    }

    @Test("a built-in player gets its measured ways, then the Play/Pause key and the panel, its page learned by itself; by window state, a way that failed there is left out")
    func builtIn() async {
        let measured = BuiltInBackups(own: .script, backups: [
            .init(.menu(name: "Playback"), BuiltInBackups.worked(in: CheckResult.WindowState.trip)),
            .init(.page(PageAccess(interface: .cef, switchAttribute: PageAccess.voiceOverSwitch)),
                  BuiltInBackups.worked(in: [.visible], failed: [.hidden])),
            .init(.panel(song: .currentTrack), [:]),
        ])
        let player = BackedUpPlayer.builtIn(MockMusicPlayer(), backups: measured, switches: BackupSwitchesStore(defaults: MemoryDefaults()))
        #expect(player.backups.map(\.kind) == [.menu, .page, .mediaKey, .panel] && player.learningPage != nil)
        // Its own way, the menu, the page, the key, the panel.
        #expect(await player.wayOrder?.order(in: .visible, for: .paused) == [0, 1, 2, 3, 4])
        #expect(await player.wayOrder?.order(in: .hidden, for: .paused) == [0, 1, 3, 4])
        // The key asks its own player's state.
        let inner = MockMusicPlayer(state: .paused)
        let quiet = BackedUpPlayer.builtIn(inner, backups: BuiltInBackups(own: .script, backups: [.init(.panel(song: nil), BuiltInBackups.worked(in: [.visible], failed: [.minimized]))]),
                                           switches: BackupSwitchesStore(defaults: MemoryDefaults()))
        #expect(await (quiet.backups[0].player as? MediaKeyWay)?.state.state() == .paused)
        // The panel goes by its own results: left out where it failed.
        #expect(await quiet.wayOrder?.order(in: .minimized, for: .paused) == [0, 1])
        withExtendedLifetime(quiet) {}
    }
}


/// A page whose player bar's Play/Pause follows `playing`: "Pause" while it
/// plays, "Play" once paused, with filler buttons, as a loaded page has.
private final class FollowingPage: WebPage {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let playing: Locked<Bool>
    private let pressed = Locked(0), released = Locked(0), shown = Locked(0)
    var presses: Int { pressed.value }
    var releases: Int { released.value }
    var shows: Int { shown.value }

    init(playing: Locked<Bool>) { self.playing = playing }

    func isTrusted(prompt: Bool) -> Bool { true }
    func buttons(pid: pid_t) -> [PageButton]? {
        [PageButton(handle: ButtonHandle(1), label: playing.value ? "Pause" : "Play")]
            + (2..<14).map { PageButton(handle: ButtonHandle($0), label: "Item \($0)") }
    }
    func hasWindow(pid: pid_t) -> Bool { true }
    func button(_ handle: ButtonHandle) -> PageButton? { buttons(pid: 0)?.first { $0.handle == handle } }
    func place(of handle: ButtonHandle) -> ButtonPlace? {
        handle == ButtonHandle(1) ? Self.place : ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain"], distanceFromBottom: 600)
    }
    func standing(of handle: ButtonHandle) -> ButtonStanding? { ButtonStanding() }
    func press(_ handle: ButtonHandle) -> Bool { pressed.increment(); return true }
    func isPlayingSound(pid: pid_t) -> Bool { true }
    func release() { released.increment() }
    func showPage(pid: pid_t) { shown.increment() }
}
