import Foundation
import Testing
@testable import CheckedPlayers
import ScriptablePlayers
import WebAppPlayers
import AutoHushKit
import AutoHushTestSupport

@Suite("CheckedPlayer")
struct CheckedPlayerTests {
    private let app = URL(fileURLWithPath: "/Applications/Jukebox.app")
    private let script = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: true)

    private func setup(_ ways: [PlayerSetup.Way]) -> PlayerSetup {
        PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: ways)
    }

    private func player(ways: [any MusicPlayer], signs: [any MusicPlayer], running: Bool = true) -> CheckedPlayer {
        CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: ways, signs: signs), reports: nil,
                      processIdentifier: { running ? 4242 : nil }, pressSleep: { _ in })
    }

    @Test("a setup keeps its ways the surest first, the panel last whatever the order found; and is kept as found")
    func setups() throws {
        let found = setup([.panel(rememberedRow: nil), .script(script), .page(.webKit)])
        #expect(found.ways == [.script(script), .page(.webKit), .panel(rememberedRow: nil)])
        #expect(try JSONDecoder().decode(PlayerSetup.self, from: JSONEncoder().encode(found)) == found)
    }

    @Test("muted instead of paused: a pause mutes it and it reads paused; a play unmutes it; once its assertion was seen, it tells")
    func muting() async throws {
        let muter = FakeMuter()
        let held = AssertionBox()
        let setup = setup([.mute])
        let player = CheckedPlayer(setup: setup, parts: CheckedPlayer.parts(for: setup, store: MemoryStore()), reports: nil,
                                   processIdentifier: { 4242 }, muter: muter, assertionHeld: { _ in held.value })
        #expect(player.pausesByMuting && player.controlPermission == .systemAudioRecording && !player.canFade)
        held.value = true
        #expect(await player.playerState() == .playing)
        try await player.pause()
        #expect(muter.isMuted)
        #expect(await player.playerState() == .paused) // still plays, muted: our pause
        try await player.play()
        #expect(!muter.isMuted)
        held.value = false
        #expect(await player.playerState() == .paused) // its assertion seen: without it, it's paused

        #expect(player.checksItsPresses) // a mute always takes: PressCheck never checks it

        player.allowTaps(false) // AntiDot mode: no taps, no mute
        await #expect(throws: MusicPlayerError.playerCommandFailed(.muteUnavailable)) { try await player.pause() }
    }

    @Test("muted, then quit: what the mute stood for goes with it")
    func mutedThenQuit() async throws {
        let muter = FakeMuter()
        let running = PIDValue(4242)
        let setup = setup([.mute])
        let player = CheckedPlayer(setup: setup, parts: CheckedPlayer.parts(for: setup, store: MemoryStore()), reports: nil,
                                   processIdentifier: { running.value }, muter: muter, assertionHeld: { _ in true })
        try await player.pause()
        #expect(muter.isMuted)
        running.value = nil
        #expect(await player.playerState() == .notRunning)
        #expect(!muter.isMuted)
        running.value = 4343 // opened again, playing: it's heard, not taken for paused
        #expect(await player.playerState() == .playing)
    }

    @Test("released, its page's switch goes back off and a mute is lifted, whenever it's asked")
    func release() async throws {
        let muter = FakeMuter()
        let setup = setup([.mute])
        let muted = CheckedPlayer(setup: setup, parts: CheckedPlayer.parts(for: setup, store: MemoryStore()), reports: nil,
                                  processIdentifier: { 4242 }, muter: muter, assertionHeld: { _ in true })
        try await muted.pause()
        #expect(muted.releasesOnQuit)
        await muted.release()
        #expect(!muter.isMuted)
        #expect(await muted.playerState() == .playing)

        let page = StubPage()
        let paged = CheckedPlayer(setup: self.setup([.page(.webKit)]), parts: .init(ways: [], signs: [], page: page.player()),
                                  reports: nil, processIdentifier: { 4242 })
        #expect(paged.releasesOnQuit)
        await paged.release()
        #expect(page.releases == 1)
    }

    @Test("its page's mute in place of a pause is its own: allowed taps, a forgotten pause, AntiDot mode")
    func pageMute() async {
        let page = StubPage()
        let muter = FakeMuter()
        let paged = CheckedPlayer(setup: setup([.page(.webKit)]), parts: .init(ways: [], signs: [], page: page.player(muter: muter)),
                                  reports: nil, processIdentifier: { 4242 })
        // Its button says Play while it's heard (an ad): muted instead.
        #expect(await paged.muteIfPlayingAnyway())
        #expect(muter.isMuted)
        await paged.forgetPause()
        #expect(await paged.muteIfPlayingAnyway() == false) // the pause it stood for is forgotten
        paged.allowTaps(false)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!muter.isMuted) // AntiDot mode lifts it
        #expect(await paged.muteIfPlayingAnyway() == false) // and mutes nothing
        paged.allowTaps(true)
        #expect(await paged.muteIfPlayingAnyway())
    }

    @Test("only an app whose page is a way and that needs the launch option can need reopening")
    func reopenNeed() async {
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(await menu.needsReopen() == false)
        var page = setup([.page(.webKit)])
        page.needsLaunchOption = true
        // Not running: nothing to reopen.
        #expect(await CheckedPlayer(setup: page, reports: nil, store: MemoryStore()).needsReopen() == false)
    }

    @Test("it's an app, controlled as its first way needs, faded when its script has a volume")
    func basics() {
        let scripted = CheckedPlayer(setup: setup([.script(script), .menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(scripted.kind == .checkedApp)
        #expect(scripted.controlPermission == .automation(player: "Jukebox"))
        #expect(scripted.canFade)
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemoryStore())
        #expect(menu.controlPermission == .accessibility(player: "Jukebox"))
        #expect(!menu.canFade)
    }

    @Test("a press goes to the first way; one that fails hands it to the next")
    func fallsBack() async throws {
        let first = MockMusicPlayer(state: .playing), second = MockMusicPlayer(state: .playing)
        try await player(ways: [first, second], signs: []).pause()
        #expect(await first.pauseCallCount == 1)
        #expect(await second.pauseCallCount == 0)

        await first.setFailPause(MusicPlayerError.playerNotResponding)
        try await player(ways: [first, second], signs: []).pause()
        #expect(await second.pauseCallCount == 1)

        await second.setFailPause(MusicPlayerError.playerCommandFailed(.pressFailed))
        await #expect(throws: MusicPlayerError.playerNotResponding) {
            try await player(ways: [first, second], signs: []).pause()
        }
    }

    @Test("it checks its own presses by its sure signs: one that doesn't take is made again, then the next way gets it")
    func checksItsPresses() async throws {
        let first = MockMusicPlayer(state: .playing), second = MockMusicPlayer(state: .playing)
        await first.setIgnoredPresses(2)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [first, second], signs: [first]),
                                    reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in })
        #expect(jukebox.checksItsPresses)
        // `first` is the sign too: it never shows the pause, so `second` is
        // pressed, and checked by it in turn: it fails the same.
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await jukebox.pause() }
        #expect(await first.pauseCallCount == 2)
        #expect(await second.pauseCallCount == 2)
        // Followed, a press is made once.
        let followed = MockMusicPlayer(state: .playing)
        try await CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [followed], signs: [followed]),
                                reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in }).pause()
        #expect(await followed.pauseCallCount == 1)
    }

    @Test("with no sure sign (its sound only), a press isn't made twice")
    func noSureSign() async throws {
        let way = MockMusicPlayer(state: .playing)
        await way.setIgnoredPresses(1)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [way], signs: []),
                                    reports: nil, processIdentifier: { 4242 }, soundOn: { _ in true }, pressSleep: { _ in })
        try await jukebox.pause()
        #expect(await way.pauseCallCount == 1)
        #expect(await jukebox.playerState() == .playing) // its sound still on: what it reads, not what checks a press
    }

    @Test("a script that only toggles, with no state, goes by the player's other signs")
    func toggleState() async throws {
        let late = LateState()
        let toggles = MockMusicPlayer(state: .unknown), sign = MockMusicPlayer(state: .playing)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]),
                                    parts: .init(ways: [toggles], signs: [sign], toggleState: late),
                                    reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in })
        #expect(await late.state() == .playing)
        await sign.overrideState(.paused)
        #expect(await late.state() == .paused)
        _ = jukebox
    }

    @Test("a report of a pause while it's heard is stale: its reports count no more")
    func staleReport() async {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.jukebox (\(getpid())) Jukebox ❯] PlaybackState changed from Playing to Paused", to: &clients)
        let heard = Heard(true)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients), processIdentifier: { 4242 },
                                    levelProbe: heard, soundOn: { _ in true })
        #expect(await jukebox.playerState() == .playing) // heard: the report of a pause is stale
        #expect(heard.listens == 1)
        #expect(await jukebox.playerState() == .playing)
        #expect(heard.listens == 1) // not asked again

        let silent = Heard(false)
        let quiet = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                  reports: NowPlayingReports(clients: clients), processIdentifier: { 4242 },
                                  levelProbe: silent, soundOn: { _ in true })
        #expect(await quiet.playerState() == .paused) // its output open, but silent: paused, as it reports
        #expect(await quiet.playerState() == .paused)
        #expect(silent.listens == 1) // once per report
        quiet.allowTaps(false)
    }

    @Test("its state is the surest sign that answers; not running, it isn't asked")
    func state() async {
        let script = MockMusicPlayer(state: .paused), page = MockMusicPlayer(state: .playing)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .paused)
        await script.setUnansweredStateQueries(1)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .playing)
        #expect(await player(ways: [script], signs: [script, page], running: false).playerState() == .notRunning)
    }

    @Test("every setup is a player, one not installed with no place; each kept while its setup stays the same")
    func players() throws {
        let installed = FileManager.default.temporaryDirectory.appendingPathComponent("Checked-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: installed) }
        let store = MemoryStore()
        store.save(PlayerSetup(bundleID: "com.example.installed", name: "Installed", appURL: installed, ways: [.menu(menuName: "Play")]))
        store.save(PlayerSetup(bundleID: "com.example.gone", name: "Gone", appURL: URL(fileURLWithPath: "/nonexistent/Gone.app"),
                               ways: [.menu(menuName: "Play")]))
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        let first = players.current()
        #expect(Set(first.map(\.bundleID)) == ["com.example.installed", "com.example.gone"])
        #expect(first.first { $0.bundleID == "com.example.installed" }?.installedURL == installed)
        #expect(first.first { $0.bundleID == "com.example.gone" }.map { $0.installedURL == nil } == true)
        let again = players.current()
        #expect(again.first { $0.bundleID == "com.example.installed" } === first.first { $0.bundleID == "com.example.installed" })
    }

    @Test("an app moved since its check is found where it is now, and kept so")
    func moved() throws {
        let now = FileManager.default.temporaryDirectory.appendingPathComponent("Moved-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: now, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: now) }
        let store = MemoryStore()
        store.save(PlayerSetup(bundleID: "com.example.moved", name: "Moved", appURL: URL(fileURLWithPath: "/nonexistent/Moved.app"),
                               ways: [.menu(menuName: "Play")]))
        let players = CheckedPlayers(store: store, locate: { $0 == "com.example.moved" ? now : nil })
        #expect(players.current().first?.setup.appURL == now)
        #expect(store.setups().first?.appURL == now)
    }
}

/// Mutes kept in memory.
final class FakeMuter: AudioMuting, @unchecked Sendable {
    private let lock = NSLock()
    private var muted: Set<pid_t> = []
    var allowed = true
    var isMuted: Bool { lock.withLock { !muted.isEmpty } }
    func mute(appPID: pid_t) -> Bool { lock.withLock { allowed ? muted.insert(appPID).inserted || true : false } }
    func unmute(appPID: pid_t) { lock.withLock { _ = muted.remove(appPID) } }
}

/// Setups kept in memory.
final class MemoryStore: PlayerSetupStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String: PlayerSetup] = [:]
    func setups() -> [PlayerSetup] { lock.withLock { Array(kept.values) } }
    func save(_ setup: PlayerSetup) { lock.withLock { kept[setup.bundleID] = setup } }
    func forget(_ bundleID: String) { lock.withLock { kept[bundleID] = nil } }
}

/// Whether the app holds its keep-awake assertion, as the test says.
final class AssertionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    var value: Bool {
        get { lock.withLock { held } }
        set { lock.withLock { held = newValue } }
    }
}

/// A pid that comes and goes, as the test says.
final class PIDValue: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t?
    init(_ pid: pid_t?) { self.pid = pid }
    var value: pid_t? {
        get { lock.withLock { pid } }
        set { lock.withLock { pid = newValue } }
    }
}

/// Whether the app can be heard, as the test says; how often it listened.
final class Heard: AudioLevelProbing, @unchecked Sendable {
    private let lock = NSLock()
    private let audible: Bool
    private var count = 0
    init(_ audible: Bool) { self.audible = audible }
    var listens: Int { lock.withLock { count } }
    func isAudible(appPID: pid_t) -> Bool { lock.withLock { count += 1; return audible } }
}

/// An added app's page in memory: its player bar's Play/Pause says "Play"
/// (with filler buttons, as a loaded page has) while its sound is on.
final class StubPage: WebPage, @unchecked Sendable {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let lock = NSLock()
    private var released = 0
    var releases: Int { lock.withLock { released } }

    /// Its page's player, as an added app's: its button learned already.
    func player(muter: any AudioMuting = FakeMuter()) -> SafariWebAppPlayer {
        let app = SafariWebApp(bundleID: "com.example.jukebox", name: "Jukebox", url: URL(fileURLWithPath: "/Applications/Jukebox.app"))
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Self.place])
        return SafariWebAppPlayer(app: app, kind: .app, page: self, store: StubRecipes(recipe), muter: muter,
                                  levelProbe: Heard(true), processIdentifier: { 4242 })
    }

    func isTrusted(prompt: Bool) -> Bool { true }
    func buttons(pid: pid_t) -> [PageButton]? {
        [PageButton(handle: ButtonHandle(1), label: "Play")] + (2..<14).map { PageButton(handle: ButtonHandle($0), label: "Item \($0)") }
    }
    func hasWindow(pid: pid_t) -> Bool { true }
    func button(_ handle: ButtonHandle) -> PageButton? { buttons(pid: 0)?.first { $0.handle == handle } }
    func place(of handle: ButtonHandle) -> ButtonPlace? {
        handle == ButtonHandle(1) ? Self.place : ButtonPlace(path: ["AXGroup", "AXGroup:AXLandmarkMain"], distanceFromBottom: 600)
    }
    func standing(of handle: ButtonHandle) -> ButtonStanding? { ButtonStanding() }
    func press(_ handle: ButtonHandle) -> Bool { true }
    func isPlayingSound(pid: pid_t) -> Bool { true }
    func release() { lock.withLock { released += 1 } }
}

/// One learned button, for every app.
final class StubRecipes: PlayPauseRecipeStore, @unchecked Sendable {
    private let recipe: PlayPauseRecipe
    init(_ recipe: PlayPauseRecipe) { self.recipe = recipe }
    func recipe(for bundleID: String) -> PlayPauseRecipe? { recipe }
    func save(_ recipe: PlayPauseRecipe, for bundleID: String) {}
    func forget(for bundleID: String) {}
}
