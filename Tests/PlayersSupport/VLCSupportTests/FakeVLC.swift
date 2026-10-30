import AppKit
import Foundation
import Testing
import os
import AutoHushKit
import PlayersTestSupport
@testable import ScriptablePlayers
@testable import VLCSupport

/// VLC as its Apple events show it, without VLC: what it answers, and what
/// it was sent.
final class FakeVLC: FakeAppleEventApp {
    struct State: AppleEventAppState {
        var pid: pid_t? = 4242
        var playing: Bool? = true
        /// -1 without an item.
        var currentTime: Int? = 12
        /// VLC's own 0–512.
        var volume = 256
        /// Every event fails, as when VLC doesn't answer.
        var fails = false
        /// What was sent, e.g. "ask" (for consent), "get AAPL", "set AAAV 256", "VLC1".
        var sent: [String] = []
    }

    let state: OSAllocatedUnfairLock<State>

    init(_ change: (inout State) -> Void = { _ in }) {
        var initial = State()
        change(&initial)
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    func send(_ makeEvent: @escaping @Sendable (pid_t) -> NSAppleEventDescriptor, to pid: pid_t) async throws -> PlayerReply {
        let event = makeEvent(pid)
        let kind = (event.eventClass, event.eventID)
        let read = SentEvent(event)
        let (property, value) = (read.property, read.value)
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
