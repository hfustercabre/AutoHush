import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("StatusPresentation")
struct StatusPresentationTests {

    // MARK: - PlaybackState symbolName

    @Test("musicPlaying uses play.circle.fill")
    func spotifyPlayingSymbol() {
        #expect(PlaybackState.musicPlaying.symbolName == "play.circle.fill")
    }

    @Test("pausedByMonitor uses pause.circle.fill")
    func pausedByMonitorSymbol() {
        #expect(PlaybackState.pausedByMonitor.symbolName == "pause.circle.fill")
    }

    @Test("musicIdle uses music.note")
    func spotifyIdleSymbol() {
        #expect(PlaybackState.musicIdle.symbolName == "music.note")
    }

    @Test("playingElsewhere uses a speaker symbol and says where Spotify plays")
    func spotifyPlayingElsewherePresentation() {
        #expect(PlaybackState.playingElsewhere.symbolName == "hifispeaker.fill")
        #expect(PlaybackState.playingElsewhere.statusLine == "Music is playing on another device")
    }

    // MARK: - PlaybackState statusLine

    @Test("musicPlaying status line is descriptive")
    func spotifyPlayingStatusLine() {
        #expect(PlaybackState.musicPlaying.statusLine == "Music is playing")
    }

    @Test("pausedByMonitor status line is descriptive")
    func pausedByMonitorStatusLine() {
        #expect(PlaybackState.pausedByMonitor.statusLine == "Music paused — another app is playing")
    }

    @Test("musicIdle status line is descriptive")
    func spotifyIdleStatusLine() {
        #expect(PlaybackState.musicIdle.statusLine == "No music playing")
    }

    // MARK: - AppHealthState symbolName

    @Test("starting uses arrow.triangle.2.circlepath")
    func startingSymbol() {
        #expect(AppHealthState.starting.symbolName == "arrow.triangle.2.circlepath")
    }

    @Test("ready keeps fallback speaker.wave.2.fill")
    func readySymbol() {
        #expect(AppHealthState.ready.symbolName == "speaker.wave.2.fill")
    }

    @Test("degraded uses exclamationmark.triangle.fill")
    func degradedSymbol() {
        #expect(AppHealthState.degraded("x").symbolName == "exclamationmark.triangle.fill")
    }

    @Test("needsPermission uses lock.trianglebadge.exclamationmark.fill")
    func needsPermissionSymbol() {
        #expect(AppHealthState.needsPermission("x").symbolName == "lock.trianglebadge.exclamationmark.fill")
    }

    @Test("failed uses speaker.slash.fill")
    func failedSymbol() {
        #expect(AppHealthState.failed("x").symbolName == "speaker.slash.fill")
    }

    // MARK: - AppHealthState statusLine

    @Test("starting shows Starting services")
    func startingStatusLine() {
        #expect(AppHealthState.starting.statusLine == "Starting services")
    }

    @Test("ready shows Monitoring media playback")
    func readyStatusLine() {
        #expect(AppHealthState.ready.statusLine == "Monitoring media playback")
    }

    @Test("degraded surfaces its associated message")
    func degradedStatusLine() {
        #expect(AppHealthState.degraded("Audio monitor restarting").statusLine == "Audio monitor restarting")
    }

    @Test("needsPermission surfaces its associated message")
    func needsPermissionStatusLine() {
        let msg = "Grant Automation access to control Spotify"
        #expect(AppHealthState.needsPermission(msg).statusLine == msg)
    }

    @Test("failed surfaces its associated message")
    func failedStatusLine() {
        #expect(AppHealthState.failed("Monitor failed hard").statusLine == "Monitor failed hard")
    }
}
