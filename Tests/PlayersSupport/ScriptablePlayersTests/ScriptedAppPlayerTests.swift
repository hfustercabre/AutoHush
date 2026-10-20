import AppKit
import Foundation
import PlayersTestSupport
import Testing
import os
import AutoHushKit
import AutoHushTestSupport
@testable import ScriptablePlayers

@Suite("ScriptedAppPlayer")
struct ScriptedAppPlayerTests {
    private func player(_ setup: ScriptSetup, app: FakeScriptedApp) -> ScriptedAppPlayer {
        ScriptedAppPlayer(bundleID: "com.example.jukebox", name: "Jukebox", setup: setup, channel: app)
    }

    @Test("its consent is asked first; its own pause and play are sent as they are; its state is its player state; with no volume, none is read or set")
    func pauseAndPlay() async throws {
        let app = FakeScriptedApp()
        let jukebox = player(ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false),
                             app: app)
        try await jukebox.verifyControlAccess()
        #expect(await jukebox.playerState() == .playing)
        try await jukebox.pause()
        #expect(await jukebox.playerState() == .paused)
        try await jukebox.play()
        #expect(!jukebox.canFade)
        #expect(await jukebox.volume() == nil)
        try await jukebox.setVolume(30)
        #expect(app.sent == ["ask", "get pPlS", "jukePaus", "get pPlS", "jukePlay"])
    }

    @Test("a toggle is sent only from the opposite state, read by script")
    func toggleByItsState() async throws {
        let app = FakeScriptedApp()
        let jukebox = player(ScriptSetup(commands: .toggle("jukeTogl"), state: .playerState, hasVolume: true), app: app)
        try await jukebox.play() // playing already: nothing sent
        #expect(app.sent == ["get pPlS"])
        try await jukebox.pause()
        #expect(app.sent == ["get pPlS", "get pPlS", "jukeTogl"])
        #expect(jukebox.canFade)
        #expect(!jukebox.checksItsPresses) // checked as any player's press
    }

    @Test("a toggle with no state of its own goes by the app's other signs, which check it: never sent twice; none answering, it's never sent")
    func toggleByOtherSigns() async throws {
        let app = FakeScriptedApp()
        let answers = Locked(PlayerState.playing) // `.unknown`: the other signs don't answer
        let jukebox = ScriptedAppPlayer(bundleID: "com.example.jukebox", name: "Jukebox",
                                        setup: ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false),
                                        toggleState: { answers.value == .unknown ? .unknown : app.state.withLock { $0.playing } ? .playing : .paused },
                                        channel: app, sleep: { _ in })
        #expect(jukebox.checksItsPresses)
        #expect(await jukebox.playerState() == .unknown)
        try await jukebox.pause()
        #expect(app.sent == ["jukeTogl"])
        try await jukebox.pause() // paused already
        #expect(app.sent == ["jukeTogl"])
        // Not shown within its wait: it fails, without a second toggle undoing a late first.
        app.state.withLock { $0.ignoresToggle = true }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.pressIgnored)) { try await jukebox.play() }
        #expect(app.sent == ["jukeTogl", "jukeTogl"])
        answers.value = .unknown
        await #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) { try await jukebox.play() }
        #expect(app.sent == ["jukeTogl", "jukeTogl"])
        // Given no other signs at all, it's never sent either.
        let signless = player(ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false), app: app)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) { try await signless.pause() }
        #expect(app.sent == ["jukeTogl", "jukeTogl"])
    }

    @Test("not running, it isn't asked; a read that fails says nothing, and the next that works tells again")
    func unanswered() async {
        let gone = FakeScriptedApp { $0.pid = nil }
        let setup = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false)
        #expect(await player(setup, app: gone).playerState() == .notRunning)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await player(setup, app: gone).verifyControlAccess() }
        #expect(gone.sent.isEmpty)
        let busy = FakeScriptedApp { $0.fails = true }
        let jukebox = player(setup, app: busy)
        #expect(await jukebox.playerState() == .unknown)
        #expect(await jukebox.playerState() == .unknown)
        busy.state.withLock { $0.fails = false }
        #expect(await jukebox.playerState() == .playing)
    }

    /// Song A, in front, paused by the user, at 60 %; Song B plays at 80 %.
    private func twoSongsApp() -> FakeScriptedApp {
        FakeScriptedApp {
            $0.documents = [("Song A", false), ("Song B", true)]
            $0.documentVolumes = ["Song A": 0.6, "Song B": 0.8]
        }
    }

    /// A player with a document's own volume, as QuickTime Player is.
    private func documentVolumePlayer(_ app: FakeScriptedApp) -> ScriptedAppPlayer {
        player(ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), actsOnDocuments: true,
                           state: .documents(documentClass: "docu", playing: "jPly"), hasVolume: false, documentVolume: "volu"), app: app)
    }

    @Test("a document's own volume (QuickTime Player's) is read from and set on the one playing, never on another (the front one)")
    func documentVolume() async throws {
        let app = twoSongsApp()
        let quickTime = documentVolumePlayer(app)
        #expect(quickTime.canFade)
        #expect(await quickTime.volume() == 80)
        try await quickTime.setVolume(30)
        #expect(app.state.withLock { $0.documentVolumes } == ["Song A": 0.6, "Song B": 0.3])
    }

    @Test("a document's own volume stays the one it fades when that one stops during the fade-out")
    func documentVolumeOfTheOneItFades() async throws {
        let app = twoSongsApp()
        let quickTime = documentVolumePlayer(app)
        try await quickTime.setVolume(30)
        // Song B stops during the fade-out: the rest of it, and the volume set back, are still Song B's.
        app.state.withLock { $0.documents[1].playing = false }
        try await quickTime.setVolume(20)
        try await quickTime.setVolume(80)
        #expect(app.state.withLock { $0.documentVolumes } == ["Song A": 0.6, "Song B": 0.8])
    }

    @Test("paused, a document's own volume is read from and set on the one it paused")
    func documentVolumeOfTheOneItPaused() async throws {
        let app = twoSongsApp()
        let quickTime = documentVolumePlayer(app)
        // The volume set back meanwhile, and the next fade-in's, are the one it paused.
        try await quickTime.pause()
        try await quickTime.setVolume(80)
        #expect(await quickTime.volume() == 80)
        #expect(app.state.withLock { $0.documentVolumes } == ["Song A": 0.6, "Song B": 0.8])
    }

    @Test("a play that failed is tried again on the document it paused, with its volume")
    func documentPlayTriedAgain() async throws {
        let app = twoSongsApp()
        let quickTime = documentVolumePlayer(app)
        try await quickTime.pause()
        try await quickTime.setVolume(1)
        // Its play times out: the volume set back, and the play tried again, still go to Song B.
        app.state.withLock { $0.failsCommands = true }
        await #expect(throws: MusicPlayerError.playerNotResponding) { try await quickTime.play() }
        app.state.withLock { $0.failsCommands = false }
        try await quickTime.setVolume(80)
        try await quickTime.play()
        #expect(app.commands == ["jukePaus Song B", "jukePlay Song B", "jukePlay Song B"])
        #expect(app.state.withLock { $0.documentVolumes } == ["Song A": 0.6, "Song B": 0.8])
    }

    @Test("with the document it paused and played closed, no volume is read or set, not even the front one's")
    func noDocumentVolume() async throws {
        let app = twoSongsApp()
        let quickTime = documentVolumePlayer(app)
        try await quickTime.pause()
        try await quickTime.play()
        // Song B closed: no volume is read or set, not even the front one's.
        app.state.withLock { $0.documents = [("Song A", false)] }
        let sent = app.sent.count
        #expect(await quickTime.volume() == nil)
        try await quickTime.setVolume(50)
        #expect(app.state.withLock { $0.documentVolumes } == ["Song A": 0.6, "Song B": 0.8])
        #expect(app.sent.count > sent) // the documents were read…
        #expect(app.sent.dropFirst(sent).allSatisfy { $0.hasSuffix("of docu") }) // …and only them
    }

    /// A player told by its documents (of class "docu", playing by "jPly"),
    /// as QuickTime Player is.
    private static let documentsSetup = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), actsOnDocuments: true,
                                                    state: .documents(documentClass: "docu", playing: "jPly"), hasVolume: false)

    /// Three documents open: Song A and Song C play, Song B doesn't.
    private func documentsApp() -> FakeScriptedApp {
        FakeScriptedApp { $0.documents = [("Song A", true), ("Song B", false), ("Song C", true)] }
    }

    @Test("by its documents: it plays while one does")
    func playsByItsDocuments() async {
        let quickTime = player(Self.documentsSetup, app: documentsApp())
        #expect(await quickTime.playerState() == .playing)
    }

    @Test("by its documents: a pause goes to each one playing")
    func pausesEachDocument() async throws {
        let app = documentsApp()
        let quickTime = player(Self.documentsSetup, app: app)
        try await quickTime.pause()
        #expect(app.commands == ["jukePaus Song A", "jukePaus Song C"])
        #expect(await quickTime.playerState() == .paused)
    }

    @Test("by its documents: a play goes back to those it paused still open, never to another (the front one)")
    func playsWhatItPaused() async throws {
        let app = documentsApp()
        let quickTime = player(Self.documentsSetup, app: app)
        try await quickTime.pause()
        app.state.withLock { _ = $0.documents.removeLast() } // Song C closed meanwhile
        try await quickTime.play()
        #expect(app.commands == ["jukePaus Song A", "jukePaus Song C", "jukePlay Song A"]) // not Song B: it wasn't paused by us
        // Only one open, which it didn't pause: nothing is played, not even the front one, which the user paused.
        app.state.withLock { $0.documents = [("Song B", false)] }
        #expect(await quickTime.playerState() == .paused)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try await quickTime.play() }
        #expect(app.commands.count == 3)
    }

    @Test("by its documents, having paused none (a pause handed over at an update's relaunch): a play goes to the only one open, to none of several")
    func playsTheOnlyDocument() async throws {
        let app = documentsApp()
        let relaunched = player(Self.documentsSetup, app: app)
        app.state.withLock { $0.documents = [("Song B", false), ("Song D", false)] }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try await relaunched.play() }
        app.state.withLock { $0.documents = [("Song D", false)] }
        try await relaunched.play()
        #expect(app.commands.count == 1 && app.commands.last == "jukePlay Song D")
    }

    @Test("by its documents, none open: it's stopped, and has nothing to play")
    func stoppedWithoutDocuments() async {
        let app = documentsApp()
        let quickTime = player(Self.documentsSetup, app: app)
        app.state.withLock { $0.documents = [] }
        #expect(await quickTime.playerState() == .stopped)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try await quickTime.play() }
    }

    /// A toggle, told by its playing flag and its current time, with a volume.
    private static let flagSetup = ScriptSetup(commands: .toggle("jukeTogl"), state: .playingFlag(property: "jPly", currentTime: "jTim"),
                                               hasVolume: true)

    @Test("its volume is read and set within 0–100")
    func volume() async throws {
        let app = FakeScriptedApp()
        let jukebox = player(Self.flagSetup, app: app)
        #expect(await jukebox.volume() == 50)
        try await jukebox.setVolume(130)
        try await jukebox.setVolume(-5)
        #expect(app.sent == ["get pVol", "set pVol 100", "set pVol 0"])
    }

    @MainActor
    @Test("its notification is followed when the check saw one")
    func followsItsNotification() {
        let announced = ScriptedAppPlayer(bundleID: "com.example.jukebox", name: "Jukebox", setup: Self.flagSetup,
                                          stateNotification: Notification.Name("com.example.jukebox.state"), channel: FakeScriptedApp())
        #expect(announced.makeStateObserver { _ in } is PlayerStateObserver)
        #expect(announced.stateReportDelay == 0)
    }

    @MainActor
    @Test("with no notification, it's read about once a second")
    func readOnceASecond() async {
        let polled = player(Self.flagSetup, app: FakeScriptedApp())
        #expect(polled.stateReportDelay == PolledStateObserver.reportDelay)
        var states: [PlayerState] = []
        let observer = polled.makeStateObserver { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
        observer.stop()
        #expect(states == [.playing])
    }

    @Test("its state is its playing flag's: -1 for its current time is stopped; with no current time, it's paused")
    func byItsPlayingFlag() async {
        let app = FakeScriptedApp { $0.playing = false }
        let polled = player(Self.flagSetup, app: app)
        #expect(await polled.playerState() == .paused)
        app.state.withLock { $0.currentTime = -1 }
        #expect(await polled.playerState() == .stopped)
        let timeless = player(ScriptSetup(commands: .toggle("jukeTogl"), state: .playingFlag(property: "jPly", currentTime: nil),
                                          hasVolume: true), app: app)
        #expect(await timeless.playerState() == .paused)
    }
}
