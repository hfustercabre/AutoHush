import AppKit
import Foundation
import Testing
import os
import AutoHushKit
import AutoHushTestSupport
@testable import ScriptablePlayers

/// A state the test says, read by a toggle without a state of its own.
private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state: PlayerState
    init(_ state: PlayerState) { self.state = state }
    var value: PlayerState {
        get { lock.withLock { state } }
        set { lock.withLock { state = newValue } }
    }
}

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
        let answers = StateBox(.playing) // `.unknown`: the other signs don't answer
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

    @Test("by its documents: it plays while one does; a pause goes to each one playing, a play back to those it paused still open, else to the front one; none open, it's stopped")
    func documents() async throws {
        let app = FakeScriptedApp { $0.documents = [("Song A", true), ("Song B", false), ("Song C", true)] }
        let quickTime = player(ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), actsOnDocuments: true,
                                           state: .documents(documentClass: "docu", playing: "jPly"), hasVolume: false), app: app)
        #expect(await quickTime.playerState() == .playing)
        try await quickTime.pause()
        #expect(app.commands == ["jukePaus Song A", "jukePaus Song C"])
        #expect(await quickTime.playerState() == .paused)
        app.state.withLock { _ = $0.documents.removeLast() } // Song C closed meanwhile
        try await quickTime.play()
        #expect(app.commands == ["jukePaus Song A", "jukePaus Song C", "jukePlay Song A"]) // not Song B: it wasn't paused by us
        // One open, which it didn't pause: the front one is played.
        app.state.withLock { $0.documents = [("Song B", false)] }
        #expect(await quickTime.playerState() == .paused)
        try await quickTime.play()
        #expect(app.commands.last == "jukePlay front")
        #expect(await quickTime.playerState() == .playing)
        app.state.withLock { $0.documents = [] }
        #expect(await quickTime.playerState() == .stopped)
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) { try await quickTime.play() }
    }

    @MainActor
    @Test("its volume is read and set within 0–100; its notification is followed when the check saw one, else it's read about once a second, by its playing flag (-1 for its current time: stopped)")
    func volumeAndObserver() async throws {
        let app = FakeScriptedApp()
        let setup = ScriptSetup(commands: .toggle("jukeTogl"), state: .playingFlag(property: "jPly", currentTime: "jTim"), hasVolume: true)
        let announced = ScriptedAppPlayer(bundleID: "com.example.jukebox", name: "Jukebox", setup: setup,
                                          stateNotification: Notification.Name("com.example.jukebox.state"), channel: app)
        #expect(announced.makeStateObserver { _ in } is PlayerStateObserver)
        #expect(announced.stateReportDelay == 0)
        #expect(await announced.volume() == 50)
        try await announced.setVolume(130)
        try await announced.setVolume(-5)
        #expect(app.sent == ["get pVol", "set pVol 100", "set pVol 0"])

        let polled = player(setup, app: app)
        #expect(polled.stateReportDelay == PolledStateObserver.reportDelay)
        var states: [PlayerState] = []
        let observer = polled.makeStateObserver { states.append($0) }
        observer.start()
        await TestWait.until { !states.isEmpty }
        observer.stop()
        #expect(states == [.playing])
        app.state.withLock { $0.playing = false }
        #expect(await polled.playerState() == .paused)
        app.state.withLock { $0.currentTime = -1 }
        #expect(await polled.playerState() == .stopped)
    }
}
