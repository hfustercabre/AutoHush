import Testing
@testable import AutoHush

@Suite("AppStatus")
struct AppStatusTests {
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    private let safari = AudioSource(id: "com.apple.Safari", name: "Safari")

    private func ready(_ playback: PlaybackState = .spotifyIdle) -> AppStatus {
        var status = AppStatus()
        status.setHealth(.ready)
        status.playback = playback
        return status
    }

    @Test("starts in the starting state with nothing to fix")
    func initialState() {
        let status = AppStatus()
        #expect(status.health == .starting)
        #expect(status.statusLine == "Starting services")
        #expect(status.iconSymbolName == "arrow.triangle.2.circlepath")
        #expect(status.warning == nil && !status.showsRetry && !status.dimsIcon)
    }

    @Test("when ready, icon and status line follow playback", arguments: [
        (PlaybackState.spotifyPlaying, "play.circle.fill", "Music is playing"),
        (.spotifyIdle, "music.note", "No music playing"),
        (.spotifyPlayingElsewhere, "hifispeaker.fill", "Music is playing on another device"),
    ])
    func readyFollowsPlayback(playback: PlaybackState, symbol: String, line: String) {
        let status = ready(playback)
        #expect(status.iconSymbolName == symbol)
        #expect(status.statusLine == line)
    }

    @Test("a pause names the apps that caused it")
    func pauseNamesApps() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([vlc])
        #expect(status.statusLine == "Music paused — VLC is playing")
        status.setActiveSources([vlc, chrome])
        #expect(status.statusLine == "Music paused — Google Chrome and VLC are playing")
        status.setActiveSources([vlc, chrome, safari])
        #expect(status.statusLine == "Music paused — Google Chrome and 2 other apps are playing")
        status.setActiveSources([])
        #expect(status.statusLine == "Music paused — another app is playing")
    }

    @Test("ignored apps are listed but never named as the cause of a pause")
    func ignoredAppsAreNotCauses() {
        var status = ready(.pausedByMonitor)
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        #expect(status.activeSources == [chrome, vlc])
        #expect(status.pausingSources == [chrome])
        #expect(status.isIgnored(vlc.id))
        #expect(status.statusLine == "Music paused — Google Chrome is playing")
    }

    @Test("auto-pause off replaces the status line and dims the icon")
    func autoPauseOff() {
        var status = ready(.spotifyPlaying)
        status.autoPause = .off
        #expect(status.statusLine == "Auto-pause is off")
        #expect(status.dimsIcon)
        status.autoPause = .snoozed(until: "15:30")
        #expect(status.statusLine == "Auto-pause is off until 15:30")
        #expect(status.dimsIcon)
        status.autoPause = .on
        #expect(!status.dimsIcon)
    }

    @Test("health problems take precedence over auto-pause")
    func healthBeatsAutoPause() {
        var status = AppStatus()
        status.autoPause = .off
        status.setHealth(.degraded("Spotify is not running"))
        #expect(status.statusLine == "Spotify is not running")
        #expect(!status.dimsIcon)
    }

    @Test("degraded health clears sources and offers Retry")
    func degradedClearsSources() {
        var status = ready(.spotifyPlaying)
        status.setActiveSources([chrome])
        status.setHealth(.degraded("Audio monitor restarting"))
        #expect(status.activeSources.isEmpty)
        #expect(status.iconSymbolName == "exclamationmark.triangle.fill")
        #expect(status.showsRetry)
        #expect(status.warning == nil)
    }

    @Test("missing Automation access is the one warning, with Retry")
    func automationWarning() {
        var status = AppStatus()
        status.setHealth(.needsPermission("Grant Automation access"))
        #expect(status.warning == .automationAccess)
        #expect(status.warning?.title == "Allow Spotify Automation Access…")
        #expect(status.showsRetry)
    }

    @Test("missing audio access warns only when ready")
    func audioAccessWarning() {
        var status = ready()
        status.detection = .audioLevel
        #expect(status.warning == nil)
        status.detection = .pending
        #expect(status.warning == nil)
        status.detection = .unavailable
        #expect(status.warning == .audioRecordingAccess)
        status.setHealth(.degraded("Spotify is not running"))
        #expect(status.warning == nil)
    }

    @Test("describes playing apps in natural language")
    func describePlaying() {
        #expect(AppStatus.describePlaying(["VLC"]) == "VLC is playing")
        #expect(AppStatus.describePlaying(["A", "B"]) == "A and B are playing")
        #expect(AppStatus.describePlaying(["A", "B", "C", "D"]) == "A and 3 other apps are playing")
    }

    @Test("measuring turned off is not a problem to fix")
    func disabledDetectionIsNoWarning() {
        var status = ready()
        status.detection = .disabled
        #expect(status.warning == nil)
        #expect(status.detection.statusLine == "Detection: open audio streams only")
        status.detection = .playbackSignals
        #expect(status.warning == nil)
    }
}
