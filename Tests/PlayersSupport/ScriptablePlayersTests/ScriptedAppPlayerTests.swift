import AppKit
import Foundation
import Testing
import os
import AutoHushKit
@testable import ScriptablePlayers

/// An app scripted as its dictionary allows, without the app: its player
/// state, the commands it was sent, and whether it answers.
private final class FakeScriptedApp: AppleEventSending {
    struct State {
        var pid: pid_t? = 4242
        /// `kPSP` playing, `kPSp` paused; `nil` with no state.
        var playing = true
        var fails = false
        /// What was sent: "get pPlS", or a command's code ("jukePaus").
        var sent: [String] = []
    }

    let state: OSAllocatedUnfairLock<State>

    init(_ change: (inout State) -> Void = { _ in }) {
        var initial = State()
        change(&initial)
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    var sent: [String] { state.withLock { $0.sent } }

    func processIdentifier() -> pid_t? { state.withLock { $0.pid } }

    func runningProcessIdentifier() throws -> pid_t {
        guard let pid = processIdentifier() else { throw MusicPlayerError.playerNotRunning }
        return pid
    }

    func requestPermission(pid: pid_t) async throws {}

    func send(_ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor, to pid: pid_t) async throws -> PlayerReply {
        let event = makeEvent(pid)
        let (eventClass, eventID) = (event.eventClass, event.eventID)
        let property = event.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue
        return try state.withLock { state in
            if state.fails { throw MusicPlayerError.playerNotResponding }
            if eventClass == fourCharCode("core"), eventID == fourCharCode("getd"), property == ScriptablePlayer.Code.playerStateProperty {
                state.sent.append("get pPlS")
                return PlayerReply(directObjectCode: state.playing ? ScriptablePlayer.Code.statePlaying : ScriptablePlayer.Code.statePaused)
            }
            let code = [eventClass, eventID].map { value in
                String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }, encoding: .macOSRoman) ?? "?"
            }.joined()
            state.sent.append(code)
            if code == "jukeTogl" { state.playing.toggle() }
            if code == "jukePaus" { state.playing = false }
            if code == "jukePlay" { state.playing = true }
            return PlayerReply()
        }
    }
}

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
    private func player(_ setup: ScriptSetup, app: FakeScriptedApp, toggleState: StateBox? = nil) -> ScriptedAppPlayer {
        ScriptedAppPlayer(bundleID: "com.example.jukebox", name: "Jukebox", setup: setup,
                          toggleState: { toggleState?.value ?? .unknown }, channel: app)
    }

    @Test("its own pause and play are sent as they are; its state is its player state")
    func pauseAndPlay() async throws {
        let app = FakeScriptedApp()
        let jukebox = player(ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false),
                             app: app)
        #expect(await jukebox.playerState() == .playing)
        try await jukebox.pause()
        #expect(await jukebox.playerState() == .paused)
        try await jukebox.play()
        #expect(app.sent == ["get pPlS", "jukePaus", "get pPlS", "jukePlay"])
        #expect(!jukebox.canFade)
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
    }

    @Test("a toggle with no state of its own goes by the app's other signs; none answering, it's never sent")
    func toggleByOtherSigns() async throws {
        let app = FakeScriptedApp()
        let signs = StateBox(.playing)
        let jukebox = player(ScriptSetup(commands: .toggle("jukeTogl"), state: nil, hasVolume: false), app: app, toggleState: signs)
        #expect(await jukebox.playerState() == .unknown)
        try await jukebox.pause()
        #expect(app.sent == ["jukeTogl"])
        signs.value = .paused
        try await jukebox.pause() // paused already
        #expect(app.sent == ["jukeTogl"])
        signs.value = .unknown
        await #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) { try await jukebox.play() }
        #expect(app.sent == ["jukeTogl"])
    }

    @Test("not running, it isn't asked; a read that fails says nothing, and the next that works tells again")
    func unanswered() async {
        let gone = FakeScriptedApp { $0.pid = nil }
        let setup = ScriptSetup(commands: .pauseAndPlay(pause: "jukePaus", play: "jukePlay"), state: .playerState, hasVolume: false)
        #expect(await player(setup, app: gone).playerState() == .notRunning)
        #expect(gone.sent.isEmpty)
        let busy = FakeScriptedApp { $0.fails = true }
        let jukebox = player(setup, app: busy)
        #expect(await jukebox.playerState() == .unknown)
        #expect(await jukebox.playerState() == .unknown)
        busy.state.withLock { $0.fails = false }
        #expect(await jukebox.playerState() == .playing)
    }
}
