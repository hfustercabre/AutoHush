import AppKit
import Foundation
import Testing
import AutoHushKit
import ScriptablePlayers
@testable import VLCSupport

@Suite("VLC")
struct VLCTests {
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

    @Test("without VLC running it's reported as not running, and nothing can be sent")
    func notRunning() async throws {
        // Only checked while VLC is closed: a running VLC would be asked.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "org.videolan.vlc").isEmpty else { return }
        let vlc = VLCPlayer()
        #expect(await vlc.playerState() == .notRunning)
        #expect(await vlc.volume() == nil)
        await #expect(throws: MusicPlayerError.playerNotRunning) { try await vlc.pause() }
    }
}
