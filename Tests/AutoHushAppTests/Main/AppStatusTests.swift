import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppStatus")
struct AppStatusTests {
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    private let safari = AudioSource(id: "com.apple.Safari", name: "Safari")

    /// Ready to control the Jukebox player.
    private func ready(_ playback: PlaybackState = .musicIdle) -> AppStatus {
        var status = AppStatus()
        status.playerOptions = [PlayerOption(bundleID: TestPlayer.bundleID, name: "Jukebox",
                                             appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"))]
        status.chosenPlayerID = TestPlayer.bundleID
        status.setHealth(.ready)
        status.playback = playback
        return status
    }

    @Test("starts in the starting state with nothing to fix")
    func initialState() {
        let status = AppStatus()
        #expect(status.health == .starting)
        #expect(status.statusLine == "Starting services")
        #expect(status.icon == .starting)
        #expect(status.warning == nil && !status.canRetry && !status.dimsIcon)
    }

    @Test("when ready, icon and status line follow playback", arguments: [
        (PlaybackState.musicPlaying, MenuBarIcon.playing, "Playing"),
        (.musicIdle, .noMusic, "Not playing"),
        (.playingElsewhere, .elsewhere, "Playing on another device"),
    ])
    func readyFollowsPlayback(playback: PlaybackState, icon: MenuBarIcon, line: String) {
        let status = ready(playback)
        #expect(status.icon == icon)
        #expect(status.statusLine == line)
    }

    @Test("the card is titled with the chosen player, or AutoHush while none is chosen")
    func cardTitle() {
        #expect(ready().cardTitle == "Jukebox")
        #expect(AppStatus().cardTitle == "AutoHush")
    }

    @Test("only a problem needs attention", arguments: [
        (AppHealthState.starting, false), (.ready, false), (.needsPlayer("Choose a music player"), true),
        (.degraded("Jukebox is not running"), true), (.needsPermission(.automation(player: "Jukebox")), true),
        (.failed("Monitor failed hard"), true),
    ])
    func needsAttention(health: AppHealthState, attention: Bool) {
        var status = AppStatus()
        status.setHealth(health)
        #expect(status.needsAttention == attention)
    }

    @Test("a pause names the apps that caused it")
    func pauseNamesApps() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([vlc])
        #expect(status.statusLine == "Paused — VLC is playing")
        status.setActiveSources([vlc, chrome])
        #expect(status.statusLine == "Paused — Google Chrome and VLC are playing")
        status.setActiveSources([vlc, chrome, safari])
        #expect(status.statusLine == "Paused — Google Chrome and 2 other apps are playing")
        status.setActiveSources([])
        #expect(status.statusLine == "Paused — another app is playing")
    }

    @Test("ignored apps are listed but never named as the cause of a pause")
    func ignoredAppsAreNotCauses() {
        var status = ready(.pausedByMonitor)
        status.ignoredApps = [vlc]
        status.setActiveSources([vlc, chrome])
        #expect(status.activeSources == [chrome, vlc])
        #expect(status.pausingSources == [chrome])
        #expect(status.isIgnored(vlc.id))
        #expect(status.statusLine == "Paused — Google Chrome is playing")
    }

    @Test("auto-pause off replaces the status line and dims the icon")
    func autoPauseOff() {
        var status = ready(.musicPlaying)
        status.autoPause = .off
        #expect(status.statusLine == "Auto-Pause is off")
        #expect(status.dimsIcon)
        status.autoPause = .snoozed("until 15:30")
        #expect(status.statusLine == "Auto-Pause is off until 15:30")
        #expect(status.dimsIcon)
        status.autoPause = .on
        #expect(!status.dimsIcon)
    }

    @Test("a snooze's description is refreshed at midnight before it ends, then when it ends")
    func snoozeDescriptionRefresh() {
        let calendar = TestDates.calendar
        // Off for 24 hours at 22:00: "until tomorrow 22:00" until midnight, then "until 22:00".
        #expect(AppStatus.AutoPause.nextChange(snoozedUntil: TestDates.date(3, 22), now: TestDates.date(2, 22), calendar: calendar) == TestDates.date(3, 0))
        #expect(AppStatus.AutoPause.nextChange(snoozedUntil: TestDates.date(3, 22), now: TestDates.date(3, 0), calendar: calendar) == TestDates.date(3, 22))
        // A snooze that ends today only changes when it ends.
        #expect(AppStatus.AutoPause.nextChange(snoozedUntil: TestDates.date(2, 15, 30), now: TestDates.date(2, 15), calendar: calendar) == TestDates.date(2, 15, 30))
    }

    @Test("health problems take precedence over auto-pause")
    func healthBeatsAutoPause() {
        var status = AppStatus()
        status.autoPause = .off
        status.setHealth(.degraded("Jukebox is not running"))
        #expect(status.statusLine == "Jukebox is not running")
        #expect(!status.dimsIcon)
    }

    @Test("degraded health clears sources; it ends by itself when the player opens, so no Retry")
    func degradedClearsSources() {
        var status = ready(.musicPlaying)
        status.setActiveSources([chrome])
        status.setHealth(.degraded("Jukebox is not running"))
        #expect(status.activeSources.isEmpty)
        #expect(status.icon == .attention)
        #expect(!status.canRetry)
        #expect(status.warning == nil)
    }

    @Test("Retry is offered only after a failed start nothing announces the end of", arguments: [
        (AppHealthState.retrying("Jukebox is not responding"), true), (.failed("Monitor failed hard"), true),
        (.degraded("Jukebox is not installed"), false), (.needsPermission(.automation(player: "Jukebox")), false),
        (.starting, false), (.ready, false),
    ])
    func retryOffered(health: AppHealthState, offered: Bool) {
        var status = AppStatus()
        status.setHealth(health)
        #expect(status.canRetry == offered)
        #expect(status.needsAttention == (health != .starting && health != .ready))
    }

    @Test("waiting for a music player to be chosen needs attention, but no Retry or warning")
    func waitingForPlayer() {
        var status = AppStatus()
        status.setHealth(.needsPlayer("Choose a music player"))
        #expect(status.icon == .attention)
        #expect(status.statusLine == "Choose a music player")
        #expect(!status.canRetry)
        #expect(status.warning == nil)
    }

    @Test("missing Automation access is the one warning; granting it is noticed by itself, so no Retry")
    func automationWarning() {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        #expect(status.warning == .automation(player: "Jukebox"))
        #expect(status.warning?.grantTitle == "Allow Jukebox Automation Access…")
        #expect(!status.canRetry)
    }

    @Test("missing audio access warns only when ready")
    func audioAccessWarning() {
        var status = ready()
        status.detection = .audioLevel
        #expect(status.warning == nil)
        status.detection = .pending
        #expect(status.warning == nil)
        status.detection = .unavailable
        #expect(status.warning == .systemAudioRecording)
        status.setHealth(.degraded("Jukebox is not running"))
        #expect(status.warning == nil)
    }

    @Test("measuring turned off is not a problem to fix")
    func disabledDetectionIsNoWarning() {
        var status = ready()
        status.detection = .disabled
        #expect(status.warning == nil)
        status.detection = .playbackSignals
        #expect(status.warning == nil)
    }
}
