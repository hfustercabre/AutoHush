import AppKit
import Foundation
import Testing
import os
import AutoHushKit
import ScriptablePlayers
@testable import VLCSupport

/// VLC as its Apple events show it, without VLC: what it answers, and what
/// it was sent.
private final class FakeVLC: AppleEventSending {
    struct State {
        var pid: pid_t? = 4242
        var playing: Bool? = true
        /// -1 without an item.
        var currentTime: Int? = 12
        /// VLC's own 0–512.
        var volume = 256
        /// Every event fails, as when VLC doesn't answer.
        var fails = false
        /// What was sent, e.g. "get AAPL", "set AAAV 256", "VLC1".
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
        // What the event asks, read before the lock: descriptors aren't Sendable.
        let event = makeEvent(pid)
        let kind = (event.eventClass, event.eventID)
        let property = event.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue
        let value = event.paramDescriptor(forKeyword: fourCharCode("data")).map { Int($0.int32Value) }
        let reply = try state.withLock { state -> PlayerReply? in
            if state.fails { throw MusicPlayerError.playerNotResponding }
            switch (kind.0, kind.1, property) {
            case (fourCharCode("core"), fourCharCode("getd"), VLCPlayer.Code.playingProperty):
                state.sent.append("get AAPL")
                return PlayerReply(directObjectBoolean: state.playing)
            case (fourCharCode("core"), fourCharCode("getd"), VLCPlayer.Code.currentTimeProperty):
                state.sent.append("get AACT")
                return PlayerReply(directObjectInteger: state.currentTime)
            case (fourCharCode("core"), fourCharCode("getd"), VLCPlayer.Code.audioVolumeProperty):
                state.sent.append("get AAAV")
                return PlayerReply(directObjectInteger: state.volume)
            case (fourCharCode("core"), fourCharCode("setd"), VLCPlayer.Code.audioVolumeProperty):
                state.sent.append("set AAAV \(value ?? -1)")
                state.volume = value ?? -1
                return PlayerReply()
            case (VLCPlayer.Code.suite, VLCPlayer.Code.playPause, _):
                state.sent.append("VLC1")
                state.playing = !(state.playing ?? false)
                return PlayerReply()
            default:
                return nil
            }
        }
        guard let reply else {
            Issue.record("an event VLC isn't sent: \(event)")
            return PlayerReply()
        }
        return reply
    }
}

@Suite("VLC's control")
struct VLCControlTests {
    @Test("its state comes from `playing`, then `current time` only while it doesn't play")
    func state() async {
        let playing = FakeVLC()
        #expect(await VLCPlayer(channel: playing).playerState() == .playing)
        #expect(playing.sent == ["get AAPL"])

        let paused = FakeVLC { $0.playing = false }
        #expect(await VLCPlayer(channel: paused).playerState() == .paused)
        #expect(paused.sent == ["get AAPL", "get AACT"])

        let stopped = FakeVLC { $0.playing = false; $0.currentTime = -1 }
        #expect(await VLCPlayer(channel: stopped).playerState() == .stopped)

        #expect(await VLCPlayer(channel: FakeVLC { $0.pid = nil }).playerState() == .notRunning)
        #expect(await VLCPlayer(channel: FakeVLC { $0.fails = true }).playerState() == .unknown)
        #expect(await VLCPlayer(channel: FakeVLC { $0.playing = nil }).playerState() == .unknown)
    }

    @Test("Play/Pause toggles, so it's sent only from the opposite state")
    func toggles() async throws {
        let vlc = FakeVLC()
        let player = VLCPlayer(channel: vlc)
        try await player.pause()
        #expect(vlc.sent.filter { $0 == "VLC1" }.count == 1)
        #expect(await player.playerState() == .paused)

        // Paused already: pausing again sends nothing, which would play it.
        try await player.pause()
        #expect(vlc.sent.filter { $0 == "VLC1" }.count == 1)

        try await player.play()
        #expect(vlc.sent.filter { $0 == "VLC1" }.count == 2)
        #expect(await player.playerState() == .playing)
    }

    @Test("stopped, playing sends nothing; unknown or not running, it says why")
    func refusesToGuess() async throws {
        let stopped = FakeVLC { $0.playing = false; $0.currentTime = -1 }
        try await VLCPlayer(channel: stopped).play()
        #expect(!stopped.sent.contains("VLC1"))

        await #expect(throws: MusicPlayerError.playerCommandFailed(.stateUnknown)) {
            try await VLCPlayer(channel: FakeVLC { $0.fails = true }).pause()
        }
        await #expect(throws: MusicPlayerError.playerNotRunning) {
            try await VLCPlayer(channel: FakeVLC { $0.pid = nil }).pause()
        }
    }

    @Test("a volume read is set back to VLC's exact number, another one by the scale")
    func volume() async throws {
        let vlc = FakeVLC { $0.volume = 300 }
        let player = VLCPlayer(channel: vlc)
        #expect(await player.volume() == 59)
        try await player.setVolume(59) // the fade gives it back: 300, not 302
        #expect(vlc.sent.last == "set AAAV 300")
        try await player.setVolume(50)
        #expect(vlc.sent.last == "set AAAV 256")
        try await player.setVolume(140)
        #expect(vlc.sent.last == "set AAAV 512")
        #expect(await VLCPlayer(channel: FakeVLC { $0.pid = nil }).volume() == nil)
    }
}
