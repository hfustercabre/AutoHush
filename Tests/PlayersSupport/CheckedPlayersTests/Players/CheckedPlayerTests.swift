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

@Suite("CheckedPlayer", .waitsTimeLimit)
struct CheckedPlayerTests {
    private let app = URL(fileURLWithPath: "/Applications/Jukebox.app")
    private let script = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: true)

    private func setup(_ ways: [PlayerSetup.Way]) -> PlayerSetup {
        PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox", appURL: app, ways: ways)
    }

    private func player(ways: [any MusicPlayer], signs: [any MusicPlayer], running: Bool = true) -> CheckedPlayer {
        CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: ways, signs: signs), reports: nil,
                      processIdentifier: { running ? 4242 : nil }, pressSleep: { _ in }, audioRecordingAllowed: { true })
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
                                  reports: nil, processIdentifier: { 4242 }, audioRecordingAllowed: { true })
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
                                  reports: nil, processIdentifier: { 4242 }, audioRecordingAllowed: { true })
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
                          processIdentifier: { running ? 4242 : nil }, processArguments: { _ in arguments }, audioRecordingAllowed: { true })
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
        // Gone, it can't be opened again: asked of a stand-in, as macOS shows an
        // alert for an app that isn't there.
        page.appURL = URL(fileURLWithPath: "/nonexistent/Jukebox.app")
        let asked = Locked<[URL]>([])
        let gone = CheckedPlayer(setup: page, parts: CheckedPlayer.parts(for: page, store: MemorySetupStore()), reports: nil,
                                 openWithLaunchOption: { asked.append($0); return false })
        #expect(await gone.reopen() == false)
        #expect(asked.value == [page.appURL])
    }

    @Test("it's an app, controlled as its first way needs")
    func basics() {
        let scripted = CheckedPlayer(setup: setup([.script(script), .menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore())
        #expect(scripted.kind == .checkedApp)
        #expect(scripted.controlPermission == .automation(player: "Jukebox"))
        let menu = CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore())
        #expect(menu.controlPermission == .accessibility(player: "Jukebox"))
    }

    @Test("it's faded by its script, and not by a menu")
    func fadedByItsScript() {
        #expect(CheckedPlayer(setup: setup([.script(script), .menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore()).canFade)
        #expect(!CheckedPlayer(setup: setup([.menu(menuName: "Controls")]), reports: nil, store: MemorySetupStore()).canFade)
    }

    /// The parts of a setup whose script only toggles, with no state, then
    /// has a page and a menu.
    private var toggleParts: CheckedPlayer.Parts {
        let toggle = ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false)
        return CheckedPlayer.parts(for: setup([.script(toggle), .page(.webKit), .menu(menuName: "Controls")]), store: MemorySetupStore())
    }

    /// The parts of a setup whose script has a state, and a notification announcing it.
    private var announcedParts: CheckedPlayer.Parts {
        var announced = setup([.script(script)])
        announced.stateNotification = "com.example.jukebox.playerInfo"
        return CheckedPlayer.parts(for: announced, store: MemorySetupStore())
    }

    @Test("its signs are its script with a state, its page, its menu, in that order")
    func signs() {
        // A script that only toggles, with no state, isn't a sign: it asks the others.
        let parts = toggleParts
        #expect(parts.ways.count == 3)
        #expect(parts.signs.map { "\(type(of: $0))" } == ["SafariWebAppPlayer", "MenuPlayer"])
        #expect(announcedParts.signs.map { "\(type(of: $0))" } == ["ScriptedAppPlayer"])
    }

    @Test("a script that only toggles, with no state, goes by the other signs, and neither fades nor announces")
    func toggleByOtherSigns() {
        let parts = toggleParts
        #expect(parts.toggleState != nil && parts.page != nil)
        #expect(parts.volume == nil && parts.announcing == nil && parts.hearing == nil)
    }

    @Test("a script with a state and a notification fades it and announces its state")
    func announcedByItsScript() {
        let own = announcedParts
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
                                    reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in }, audioRecordingAllowed: { true })
        #expect(jukebox.checksItsPresses)
        // `first` is the sign too: it never shows the pause, so `second` is
        // pressed, and checked by it in turn: it fails the same.
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await jukebox.pause() }
        #expect(await first.pauseCallCount == 2)
        #expect(await second.pauseCallCount == 2)
        // Followed, a press is made once.
        let followed = MockMusicPlayer(state: .playing)
        try await CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [followed], signs: [followed]),
                                reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in }, audioRecordingAllowed: { true }).pause()
        #expect(await followed.pauseCallCount == 1)
    }

    @Test("with no sure sign (its sound only), a press isn't made twice")
    func noSureSign() async throws {
        let way = MockMusicPlayer(state: .playing)
        await way.setIgnoredPresses(1)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [way], signs: []),
                                    reports: nil, processIdentifier: { 4242 }, soundOn: { _ in true }, pressSleep: { _ in }, audioRecordingAllowed: { true })
        try await jukebox.pause()
        #expect(await way.pauseCallCount == 1)
        #expect(await jukebox.playerState() == .playing) // its sound still on: what it reads, not what checks a press
    }

    @Test("it states itself only by a sure sign that answers: by its sound alone (its output on, or its level heard) never, so it's never taken to play silently")
    func statesItself() async {
        let sign = MockMusicPlayer(state: .playing)
        #expect(await player(ways: [sign], signs: [sign]).statesItself()) // its menu's item, its page's word or its script's state
        let mute = MockMusicPlayer(state: .unknown)
        #expect(await player(ways: [mute], signs: [mute]).statesItself() == false) // a sign that says nothing now

        // No sure sign: its output, on or off, tells nothing of itself.
        for soundOn in [true, false] {
            let way = MockMusicPlayer(state: .playing)
            let unsigned = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [way], signs: []), reports: nil,
                                         processIdentifier: { 4242 }, soundOn: { _ in soundOn }, pressSleep: { _ in }, audioRecordingAllowed: { true })
            #expect(await unsigned.statesItself() == false, "its output \(soundOn ? "on" : "off")")
        }

        // Told by its level (its Now Playing row doesn't follow it): never, heard or not, and it isn't listened to for it.
        var stale = setup([.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        let heard = FakeLevelProbe(audible: true)
        let byLevel = CheckedPlayer(setup: stale, parts: CheckedPlayer.parts(for: stale, store: MemorySetupStore()), reports: nil,
                                    processIdentifier: { 4242 }, levelProbe: heard, soundOn: { _ in true }, audioRecordingAllowed: { true })
        #expect(await byLevel.statesItself() == false)
        #expect(heard.listens == 0)
    }

    @Test("a script that only toggles, with no state, goes by the player's other signs")
    func toggleState() async throws {
        let late = LateState()
        let toggles = MockMusicPlayer(state: .unknown), sign = MockMusicPlayer(state: .playing)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]),
                                    parts: .init(ways: [toggles], signs: [sign], toggleState: late),
                                    reports: nil, processIdentifier: { 4242 }, pressSleep: { _ in }, audioRecordingAllowed: { true })
        #expect(await late.state() == .playing)
        await sign.overrideState(.paused)
        #expect(await late.state() == .paused)
        _ = jukebox
    }

    @Test("a report of Unknown while it's heard (Apple TV's trailers) says nothing: it isn't listened to, its sound output tells, and its reports still count")
    func unknownReport() async {
        // The reports below count their process as running without asking the
        // system (`processRuns`): both report tests once failed together under
        // Thread Sanitizer, finding no report (B4, 2026-10-25).
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.jukebox (\(getpid())) Jukebox ❯] PlaybackState changed from Paused to Unknown", to: &clients)
        let heard = FakeLevelProbe(audible: true)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                    levelProbe: heard, soundOn: { _ in true }, audioRecordingAllowed: { true })
        #expect(await jukebox.playerState() == .playing) // its output on
        #expect(heard.listens == 0) // nothing to check against its level

        NowPlayingReports.apply("[com.example.jukebox (\(getpid())) Jukebox ❯] PlaybackState changed from Unknown to Paused", to: &clients)
        let silent = FakeLevelProbe(audible: false)
        let paused = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                   reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                   levelProbe: silent, soundOn: { _ in true }, audioRecordingAllowed: { true })
        #expect(await paused.playerState() == .paused) // its output open, silent: as it reports
    }

    @Test("a report of a pause while it's heard is stale: its reports count no more; in AntiDot mode, or without Audio Recording, it isn't listened to")
    func staleReport() async {
        var clients: [pid_t: NowPlayingReports.Client] = [:]
        NowPlayingReports.apply("[com.example.jukebox (\(getpid())) Jukebox ❯] PlaybackState changed from Playing to Paused", to: &clients)
        let heard = FakeLevelProbe(audible: true)
        let jukebox = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                    levelProbe: heard, soundOn: { _ in true }, audioRecordingAllowed: { true })
        #expect(await jukebox.polledState() == .paused) // read once a second: as reported, not listened to
        #expect(heard.listens == 0)
        #expect(await jukebox.playerState() == .playing) // heard: the report of a pause is stale
        #expect(heard.listens == 1)
        #expect(await jukebox.playerState() == .playing)
        #expect(heard.listens == 1) // not asked again

        let silent = FakeLevelProbe(audible: false)
        let quiet = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                  reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                  levelProbe: silent, soundOn: { _ in true }, audioRecordingAllowed: { true })
        #expect(await quiet.playerState() == .paused) // its output open, but silent: paused, as it reports
        #expect(await quiet.playerState() == .paused)
        #expect(silent.listens == 1) // once per report

        let unheard = FakeLevelProbe(audible: true)
        let antiDot = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                    reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                    levelProbe: unheard, soundOn: { _ in true }, audioRecordingAllowed: { true })
        antiDot.allowTaps(false) // no taps: as it reports
        #expect(await antiDot.playerState() == .paused)
        #expect(unheard.listens == 0)

        let unrecorded = FakeLevelProbe(audible: true)
        let noRecording = CheckedPlayer(setup: setup([.menu(menuName: "Play")]), parts: .init(ways: [], signs: []),
                                        reports: NowPlayingReports(clients: clients, processRuns: { _ in true }), processIdentifier: { 4242 },
                                        levelProbe: unrecorded, soundOn: { _ in true }, audioRecordingAllowed: { false })
        #expect(await noRecording.playerState() == .paused) // without Audio Recording, a tap hears nothing: as it reports
        #expect(unrecorded.listens == 0)
    }

    @Test("one told by its level is listened to only when it's about to be paused or played; read once a second, its assertion tells")
    func levelOnlyForDecisions() async {
        var stale = setup([.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        let heard = FakeLevelProbe(audible: false)
        let held = Locked(false)
        let qobuz = CheckedPlayer(setup: stale, parts: CheckedPlayer.parts(for: stale, store: MemorySetupStore()), reports: nil,
                                  processIdentifier: { 4242 }, levelProbe: heard, soundOn: { _ in true }, assertionsHeld: { _ in held.value ? playing : [] }, audioRecordingAllowed: { true })
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

    /// One with a stale panel row, told between decisions by the assertions `held`.
    private func asserting(_ held: Locked<Set<PowerAssertion>>) -> CheckedPlayer {
        var stale = setup([.panel(rememberedRow: nil)])
        stale.panelRowIsStale = true
        return CheckedPlayer(setup: stale, parts: CheckedPlayer.parts(for: stale, store: MemorySetupStore()), reports: nil,
                             processIdentifier: { 4242 }, levelProbe: FakeLevelProbe(audible: false), soundOn: { _ in true },
                             assertionsHeld: { _ in held.value }, audioRecordingAllowed: { true })
    }

    @Test("its assertions tell by AntiDot mode's rule: one keeping only the display awake tells nothing")
    func displayAssertionTellsNothing() async {
        let held = Locked<Set<PowerAssertion>>([PowerAssertion(.display, "Showing a picture")])
        #expect(await asserting(held).polledState() == .unknown) // the display only: nothing told
    }

    @Test("one keeping only the display awake tells it plays when it kept the Mac awake under the same name while its sound was on (a video)")
    func videoAssertionTells() async {
        let held = Locked<Set<PowerAssertion>>([PowerAssertion(.system, "Video")]) // its video hidden keeps the Mac awake
        let player = asserting(held)
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

    /// One with its script for its volume and its announcing.
    private func scriptedPlayer(_ script: MockMusicPlayer) -> CheckedPlayer {
        CheckedPlayer(setup: setup([.script(self.script)]), parts: .init(ways: [script], signs: [script], volume: script, announcing: script),
                      reports: nil, processIdentifier: { 4242 }, audioRecordingAllowed: { true })
    }

    /// One with its page only, which `muter` mutes.
    private func pagedPlayer(muter: FakeMuter) -> CheckedPlayer {
        let page = StubPage().player(muter: muter)
        return CheckedPlayer(setup: setup([.page(.webKit)]), parts: .init(ways: [page], signs: [page], page: page),
                             reports: nil, processIdentifier: { 4242 }, audioRecordingAllowed: { true })
    }

    @Test("its volume is its script's")
    func volume() async throws {
        let script = MockMusicPlayer()
        await script.setVolumeLevel(40)
        let scripted = scriptedPlayer(script)
        #expect(await scripted.volume() == 40)
        try await scripted.setVolume(25)
        #expect(await script.volumeHistory == [25])
    }

    @MainActor
    @Test("it's watched by its script's notification")
    func watchedByItsScript() {
        let scripted = scriptedPlayer(MockMusicPlayer())
        #expect(scripted.makeStateObserver { _ in } is MockStateObserver) // its script's own
        #expect(scripted.stateReportDelay == 0)
    }

    @Test("with no script, it has no volume")
    func noVolume() async {
        #expect(await pagedPlayer(muter: FakeMuter()).volume() == nil) // no fades
    }

    @MainActor
    @Test("with no script, it's read about once a second, by its page")
    func readOnceASecond() async {
        let paged = pagedPlayer(muter: FakeMuter())
        #expect(paged.stateReportDelay == PolledStateObserver.reportDelay)
        #expect(await paged.muteIfPlayingAnyway()) // its button says Play while it's heard (an ad): muted instead
        var states: [PlayerState] = []
        let observer = paged.makeStateObserver { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
        #expect(states == [.paused]) // read by its page: muted in place of a pause
        observer.stop()
    }

    @MainActor
    @Test("stopping its reading lifts its page's mute: the app is never left silent")
    func stoppingLiftsTheMute() async {
        let muter = FakeMuter()
        let paged = pagedPlayer(muter: muter)
        #expect(await paged.muteIfPlayingAnyway())
        var states: [PlayerState] = []
        let observer = paged.makeStateObserver { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
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
        let folder = TemporaryFolder("CheckedPlayerTests")
        let installed = folder.appending(path: "Checked.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
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
        withExtendedLifetime(folder) {}
    }

    @Test("an app moved since its check is found where it is now, and kept so")
    func moved() throws {
        let folder = TemporaryFolder("CheckedPlayerTests")
        let now = folder.appending(path: "Moved.app")
        try FileManager.default.createDirectory(at: now, withIntermediateDirectories: true)
        let store = MemorySetupStore()
        store.save(PlayerSetup(bundleID: "com.example.moved", name: "Moved", appURL: URL(fileURLWithPath: "/nonexistent/Moved.app"),
                               ways: [.menu(menuName: "Play")]))
        let players = CheckedPlayers(store: store, locate: { $0 == "com.example.moved" ? now : nil })
        #expect(players.current().first?.setup.appURL == now)
        #expect(store.setups().first?.appURL == now)
        withExtendedLifetime(folder) {}
    }
}
