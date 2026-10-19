import Foundation
import Testing
@testable import CheckedPlayers
import ScriptablePlayers
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// A keep-awake assertion as a player holds one while it plays.
private let playing: Set<PowerAssertion> = [PowerAssertion(.system, "Playing")]

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

    @Test("released, its page's switch goes back off, whenever it's asked")
    func release() async throws {
        let page = StubPage()
        let paged = CheckedPlayer(setup: self.setup([.page(.webKit)]), parts: .init(ways: [], signs: [], page: page.player()),
                                  reports: nil, processIdentifier: { 4242 })
        #expect(paged.releasesOnQuit)
        await paged.release()
        #expect(page.releases == 1)

        // The page its panel way reads its player bar through, where its check found its song there.
        var clued = self.setup([.panel(rememberedRow: nil)])
        #expect(!CheckedPlayer(setup: clued, reports: nil, store: MemorySetupStore()).releasesOnQuit)
        clued.panelClues = PanelClues(page: PanelClues.Page(access: .webKit, labels: ["Pause"]), script: nil)
        #expect(CheckedPlayer.parts(for: clued, store: MemorySetupStore()).cluePage?.access == .webKit)
        #expect(CheckedPlayer(setup: clued, reports: nil, store: MemorySetupStore()).releasesOnQuit)
        clued.panelClues = PanelClues(page: nil, script: .currentTrack)
        #expect(!CheckedPlayer(setup: clued, reports: nil, store: MemorySetupStore()).releasesOnQuit)
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
        await TestWait.until { !muter.isMuted } // AntiDot mode lifts it
        #expect(await paged.muteIfPlayingAnyway() == false) // and mutes nothing
        paged.allowTaps(true)
        #expect(await paged.muteIfPlayingAnyway())
    }

    @Test("only an app whose page is a way and that needs the launch option can need reopening, while it runs without it; one that's gone can't be reopened")
    func reopenNeed() async {
        func jukebox(_ setup: PlayerSetup, running: Bool = true, arguments: [String] = []) -> CheckedPlayer {
            CheckedPlayer(setup: setup, parts: CheckedPlayer.parts(for: setup, store: MemorySetupStore()), reports: nil,
                          processIdentifier: { running ? 4242 : nil }, processArguments: { _ in arguments })
        }
        var page = setup([.page(.webKit)])
        #expect(await jukebox(page).needsReopen() == false) // it doesn't need the option
        page.needsLaunchOption = true
        #expect(await jukebox(page).needsReopen())
        let opened = ["/Applications/Jukebox.app/Contents/MacOS/Jukebox", PlayerSetup.launchOption] // its own path first
        #expect(await jukebox(page, arguments: opened).needsReopen() == false)
        #expect(await jukebox(page, running: false).needsReopen() == false) // nothing to reopen
        var menu = setup([.menu(menuName: "Controls")])
        menu.needsLaunchOption = true
        #expect(await jukebox(menu).needsReopen() == false)
        page.appURL = URL(fileURLWithPath: "/nonexistent/Jukebox.app")
        #expect(await CheckedPlayer(setup: page, reports: nil, store: MemorySetupStore()).reopen() == false)
    }

    @Test("it's an app, controlled as its first way needs, faded and announced by its script; its signs are its script with a state, its page, its menu, in that order")
    func basics() {
        let scripted = CheckedPlayer(setup: setup([.script(script), .menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore())
        #expect(scripted.kind == .checkedApp)
        #expect(scripted.controlPermission == .automation(player: "Jukebox"))
        #expect(scripted.canFade)
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore())
        #expect(menu.controlPermission == .accessibility(player: "Jukebox"))
        #expect(!menu.canFade)

        // A script that only toggles, with no state, isn't a sign: it asks the others.
        let toggle = ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false)
        let parts = CheckedPlayer.parts(for: setup([.script(toggle), .page(.webKit), .menu(menuName: "Controls")]), store: MemorySetupStore())
        #expect(parts.ways.count == 3)
        #expect(parts.signs.map { "\(type(of: $0))" } == ["SafariWebAppPlayer", "MenuPlayer"])
        #expect(parts.toggleState != nil && parts.page != nil)
        #expect(parts.volume == nil && parts.announcing == nil && parts.hearing == nil)
        var announced = setup([.script(script)])
        announced.stateNotification = "com.example.jukebox.playerInfo"
        let own = CheckedPlayer.parts(for: announced, store: MemorySetupStore())
        #expect(own.signs.map { "\(type(of: $0))" } == ["ScriptedAppPlayer"])
        #expect(own.volume is ScriptedAppPlayer && own.announcing is ScriptedAppPlayer && own.toggleState == nil)
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

        try await player(ways: [first, second], signs: []).play() // a play the same
        #expect(await first.playCallCount == 1)
        #expect(await second.playCallCount == 0)
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

    @Test("a report of a pause while it's heard is stale: its reports count no more; in AntiDot mode it isn't listened to")
    func staleReport() async {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.jukebox (\(getpid())) Jukebox ❯] PlaybackState changed from Playing to Paused", to: &clients)
        let heard = FakeLevelProbe(audible: true)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients), processIdentifier: { 4242 },
                                    levelProbe: heard, soundOn: { _ in true })
        #expect(await jukebox.polledState() == .paused) // read once a second: as reported, not listened to
        #expect(heard.listens == 0)
        #expect(await jukebox.playerState() == .playing) // heard: the report of a pause is stale
        #expect(heard.listens == 1)
        #expect(await jukebox.playerState() == .playing)
        #expect(heard.listens == 1) // not asked again

        let silent = FakeLevelProbe(audible: false)
        let quiet = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                  reports: NowPlayingReports(clients: clients), processIdentifier: { 4242 },
                                  levelProbe: silent, soundOn: { _ in true })
        #expect(await quiet.playerState() == .paused) // its output open, but silent: paused, as it reports
        #expect(await quiet.playerState() == .paused)
        #expect(silent.listens == 1) // once per report

        let unheard = FakeLevelProbe(audible: true)
        let antiDot = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients), processIdentifier: { 4242 },
                                    levelProbe: unheard, soundOn: { _ in true })
        antiDot.allowTaps(false) // no taps: as it reports
        #expect(await antiDot.playerState() == .paused)
        #expect(unheard.listens == 0)
    }

    @Test("one told by its level is listened to only when it's about to be paused or played; read once a second, its assertion tells")
    func levelOnlyForDecisions() async {
        var stale = setup([.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        let heard = FakeLevelProbe(audible: false)
        let held = Locked(false)
        let qobuz = CheckedPlayer(setup: stale, parts: CheckedPlayer.parts(for: stale, store: MemorySetupStore()), reports: nil,
                                  processIdentifier: { 4242 }, levelProbe: heard, soundOn: { _ in true }, assertionsHeld: { _ in held.value ? playing : [] })
        #expect(qobuz.needsAudioLevels && !qobuz.pausesByMuting) // heard, through Audio Recording, but pressed, not muted
        #expect(await qobuz.polledState() == .unknown) // its output open, and no assertion seen yet: nothing told
        held.value = true
        #expect(await qobuz.polledState() == .playing)
        held.value = false
        #expect(await qobuz.polledState() == .paused)
        #expect(heard.listens == 0)
        #expect(await qobuz.playerState() == .paused) // about to be paused or played: listened to
        #expect(heard.listens == 1)
    }

    @Test("its assertions tell by AntiDot mode's rule: one keeping only the display awake doesn't, unless it kept the Mac awake under the same name while its sound was on (a video)")
    func assertionsByAntiDotRule() async {
        var stale = setup([.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        let held = Locked<Set<PowerAssertion>>([])
        let player = CheckedPlayer(setup: stale, parts: CheckedPlayer.parts(for: stale, store: MemorySetupStore()), reports: nil,
                                   processIdentifier: { 4242 }, levelProbe: FakeLevelProbe(audible: false), soundOn: { _ in true },
                                   assertionsHeld: { _ in held.value })
        held.value = [PowerAssertion(.display, "Showing a picture")]
        #expect(await player.polledState() == .unknown) // the display only: nothing told
        held.value = [PowerAssertion(.system, "Video")] // its video hidden keeps the Mac awake
        #expect(await player.polledState() == .playing)
        held.value = [PowerAssertion(.display, "Video")] // shown, the same one keeps only the display awake
        #expect(await player.polledState() == .playing)
        held.value = [PowerAssertion(.display, "Showing a picture")]
        #expect(await player.polledState() == .paused)
    }

    @Test("its access is checked way by way until one answers, the panel only when it's the only way")
    func access() async throws {
        let denied = MockMusicPlayer(failVerifyWith: MusicPlayerError.automationPermissionDenied), allowed = MockMusicPlayer()
        let panelAsked = Locked(false) // here: whether the panel way was asked
        let panel = PanelWay(setup: setup([.panel(rememberedRow: nil)]), remembered: nil, store: MemorySetupStore(), panel: FakePanel([]),
                             processIdentifier: { panelAsked.value = true; return nil })
        // Found first here, it's still asked last: it opens on screen.
        try await player(ways: [panel, denied, allowed], signs: []).verifyControlAccess()
        #expect(await denied.verifyCallCount == 1)
        #expect(await allowed.verifyCallCount == 1)
        // None other answering: the first one's reason, and the panel isn't asked.
        await #expect(throws: MusicPlayerError.automationPermissionDenied) {
            try await player(ways: [panel, denied], signs: []).verifyControlAccess()
        }
        #expect(!panelAsked.value)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player(ways: [panel], signs: []).verifyControlAccess() }
        #expect(panelAsked.value)
    }

    @MainActor
    @Test("its volume is its script's; it's watched by its script's notification, else read about once a second, and stopping that lifts its page's mute: the app is never left silent")
    func volumeAndObserver() async throws {
        let script = MockMusicPlayer()
        await script.setVolumeLevel(40)
        let scripted = CheckedPlayer(setup: setup([.script(self.script)]),
                                     parts: .init(ways: [script], signs: [script], volume: script, announcing: script),
                                     reports: nil, processIdentifier: { 4242 })
        #expect(await scripted.volume() == 40)
        try await scripted.setVolume(25)
        #expect(await script.volumeHistory == [25])
        #expect(scripted.makeStateObserver { _ in } is MockStateObserver) // its script's own
        #expect(scripted.stateReportDelay == 0)

        let page = StubPage(), muter = FakeMuter()
        let pagePlayer = page.player(muter: muter)
        let paged = CheckedPlayer(setup: setup([.page(.webKit)]), parts: .init(ways: [pagePlayer], signs: [pagePlayer], page: pagePlayer),
                                  reports: nil, processIdentifier: { 4242 })
        #expect(await paged.volume() == nil) // no fades
        #expect(paged.stateReportDelay == PolledStateObserver.reportDelay)
        #expect(await paged.muteIfPlayingAnyway()) // its button says Play while it's heard (an ad): muted instead
        var states: [PlayerState] = []
        let observer = paged.makeStateObserver { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
        #expect(states == [.paused]) // read by its page: muted in place of a pause
        observer.stop()
        await TestWait.until { !muter.isMuted }
    }

    @Test("its state is the surest sign that answers; not running, it isn't asked")
    func state() async {
        let script = MockMusicPlayer(state: .paused), page = MockMusicPlayer(state: .playing)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .paused)
        await script.setUnansweredStateQueries(1)
        #expect(await player(ways: [script], signs: [script, page]).playerState() == .playing)
        #expect(await player(ways: [script], signs: [script, page], running: false).playerState() == .notRunning)
    }

    @Test("every setup is a player, muted instead of paused when that's its way, one not installed with no place; each kept while its setup stays the same")
    func players() throws {
        let installed = FileManager.default.temporaryDirectory.appendingPathComponent("Checked-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: installed) }
        let store = MemorySetupStore()
        store.save(PlayerSetup(bundleID: "com.example.installed", name: "Installed", appURL: installed, ways: [.menu(menuName: "Play")]))
        store.save(PlayerSetup(bundleID: "com.example.gone", name: "Gone", appURL: URL(fileURLWithPath: "/nonexistent/Gone.app"),
                               ways: [.menu(menuName: "Play")]))
        store.save(PlayerSetup(bundleID: "com.example.muted", name: "Muted", appURL: installed, ways: [.mute]))
        let players = CheckedPlayers(store: store, locate: { _ in nil })
        let first = players.current()
        #expect(Set(first.map(\.bundleID)) == ["com.example.installed", "com.example.gone", "com.example.muted"])
        #expect(first.first { $0.bundleID == "com.example.installed" } is CheckedPlayer)
        #expect(first.first { $0.bundleID == "com.example.muted" } is MutedApp)
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
        let store = MemorySetupStore()
        store.save(PlayerSetup(bundleID: "com.example.moved", name: "Moved", appURL: URL(fileURLWithPath: "/nonexistent/Moved.app"),
                               ways: [.menu(menuName: "Play")]))
        let players = CheckedPlayers(store: store, locate: { $0 == "com.example.moved" ? now : nil })
        #expect(players.current().first?.setup.appURL == now)
        #expect(store.setups().first?.appURL == now)
    }
}

/// An added app's page in memory: its player bar's Play/Pause says "Play"
/// (with filler buttons, as a loaded page has) while its sound is on.
final class StubPage: WebPage {
    static let place = ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 40)
    private let released = Locked(0)
    var releases: Int { released.value }

    /// Its page's player, as an added app's: its button learned already.
    func player(muter: any AudioMuting = FakeMuter()) -> SafariWebAppPlayer {
        let app = SafariWebApp(bundleID: "com.example.jukebox", name: "Jukebox", url: URL(fileURLWithPath: "/Applications/Jukebox.app"))
        let recipe = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause", places: [Self.place])
        return SafariWebAppPlayer(app: app, kind: .app, page: self, store: MemoryRecipeStore([app.bundleID: recipe]), muter: muter,
                                  levelProbe: FakeLevelProbe(audible: true), processIdentifier: { 4242 })
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
    func release() { released.increment() }
}
