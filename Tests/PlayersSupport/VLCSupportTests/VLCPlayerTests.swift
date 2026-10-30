import AppKit
import Foundation
import Testing
import os
import AutoHushKit
import PlayersTestSupport
@testable import ScriptablePlayers
@testable import VLCSupport
import AutoHushTestSupport

@Suite("VLCPlayer", .appleEventCoercions, .waitsTimeLimit)
struct VLCPlayerTests {
    // Never sent: building descriptors does not contact the target process.
    private let pid: pid_t = 4242

    @Test("VLC is scripted with Apple events, fades with a cube law, and is watched by reading its state")
    @MainActor
    func identity() {
        let vlc = VLCPlayer()
        #expect(vlc.name == "VLC")
        #expect(vlc.bundleID == "org.videolan.vlc")
        #expect(vlc.controlPermission == .automation(player: "VLC"))
        #expect(vlc.volumeCurve == .cubic)
        #expect(vlc.canFade)
        #expect(vlc.makeStateObserver { _ in } is PolledStateObserver)
        #expect(vlc.stateReportDelay == PolledStateObserver.reportDelay) // a change is seen up to a read later
    }

    @Test("its state: playing, paused with an item, stopped without one (current time -1)", arguments: [
        (true, Int?(12), PlayerState.playing), (true, nil, .playing), (false, 0, .paused), (false, 95, .paused),
        (false, -1, .stopped), (false, nil, .unknown),
    ])
    func state(playing: Bool, currentTime: Int?, state: PlayerState) {
        #expect(VLCPlayer.state(playing: playing, currentTime: currentTime) == state)
    }

    @Test("VLC's 0–512 volume is AutoHush's 0–100, and back", arguments: [
        (0, 0), (256, 50), (512, 100), (128, 25), (300, 59), (600, 100),
    ])
    func volumeScale(vlc: Int, volume: Int) {
        #expect(VLCPlayer.volume(fromVLC: vlc) == volume)
        if vlc <= 512, vlc % 128 == 0 { #expect(VLCPlayer.vlcVolume(from: volume) == vlc) }
    }

    @Test("its properties are read and set with core events, and Play/Pause is VLC1 of its suite")
    func events() throws {
        let playing = ScriptablePlayer.makeGetPropertyEvent(VLCPlayer.Code.playingProperty, processIdentifier: pid)
        #expect(playing.eventClass == fourCharCode("core") && playing.eventID == fourCharCode("getd"))
        #expect(playing.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("AAPL"))

        let volume = ScriptablePlayer.makeSetPropertyEvent(VLCPlayer.Code.audioVolumeProperty, to: 300, processIdentifier: pid)
        #expect(volume.eventClass == fourCharCode("core") && volume.eventID == fourCharCode("setd"))
        #expect(volume.paramDescriptor(forKeyword: fourCharCode("----"))?.forKeyword(fourCharCode("seld"))?.typeCodeValue == fourCharCode("AAAV"))
        #expect(volume.paramDescriptor(forKeyword: fourCharCode("data"))?.int32Value == 300)

        let toggle = ScriptablePlayer.makeCommandEvent(suite: VLCPlayer.Code.suite, VLCPlayer.Code.playPause, processIdentifier: pid)
        #expect(toggle.eventClass == fourCharCode("VLC#") && toggle.eventID == fourCharCode("VLC1"))
    }

    // MARK: - Through its Apple events

    @Test("its consent is asked, then `playing` read, to check access; its state comes from `playing`, then `current time` only while it doesn't play")
    func stateFromEvents() async throws {
        let playing = FakeVLC()
        try await VLCPlayer(channel: playing).verifyControlAccess()
        #expect(playing.sent == ["ask", "get AAPL"])
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await VLCPlayer(channel: FakeVLC { $0.pid = nil }).verifyControlAccess() }
        #expect(await VLCPlayer(channel: playing).playerState() == .playing)
        #expect(playing.sent == ["ask", "get AAPL", "get AAPL"])

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

    @Test("stopped, playing sends nothing and says it has nothing to play; unknown or not running, it says why")
    func refusesToGuess() async throws {
        let stopped = FakeVLC { $0.playing = false; $0.currentTime = -1 }
        await #expect(throws: MusicPlayerError.playerCommandFailed(.nothingToPlay)) {
            try await VLCPlayer(channel: stopped).play()
        }
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
