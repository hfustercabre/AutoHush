import Foundation
import Testing
@testable import CheckedPlayers
import AutoHushKit

@Suite("MutedAppState")
struct MutedAppStateTests {
    private let start = Date(timeIntervalSince1970: 1000)

    @Test("muted for another app, it reads as paused; a gap between songs doesn't end the mute")
    func mutedReadsPaused() {
        var hush = MutedAppState()
        hush.mute()
        #expect(hush.read(playing: true, at: start) == (.paused, false))
        #expect(hush.read(playing: false, at: start.addingTimeInterval(1)) == (.paused, false))
        #expect(hush.read(playing: true, at: start.addingTimeInterval(2)) == (.paused, false)) // 1 s of silence
        #expect(hush.isMuted)
    }

    @Test("paused by the user (3 s and more) and played again: the mute is lifted and it reads as playing")
    func userPlaysAgain() {
        var hush = MutedAppState()
        hush.mute()
        _ = hush.read(playing: false, at: start)
        #expect(hush.read(playing: false, at: start.addingTimeInterval(MutedAppState.stopTime)) == (.paused, false))
        #expect(hush.read(playing: true, at: start.addingTimeInterval(5)) == (.playing, true))
        #expect(!hush.isMuted)
    }

    @Test("after a sleep it stays muted while it plays on, and is unmuted once it stops")
    func forgotten() {
        var hush = MutedAppState()
        hush.mute()
        hush.forget()
        #expect(hush.read(playing: true, at: start) == (.paused, false))
        _ = hush.read(playing: false, at: start.addingTimeInterval(1))
        #expect(hush.read(playing: false, at: start.addingTimeInterval(1 + MutedAppState.stopTime)) == (.paused, true))
        #expect(!hush.isMuted)
    }

    @Test("not muted, it reads as it plays")
    func notMuted() {
        var hush = MutedAppState()
        #expect(hush.read(playing: true, at: start) == (.playing, false))
        #expect(hush.read(playing: false, at: start) == (.paused, false))
    }
}
