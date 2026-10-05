import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("StatusPresentation")
struct StatusPresentationTests {

    // MARK: - States

    @Test("each playback state has its icon, label and status line", arguments: [
        (PlaybackState.musicPlaying, MenuBarIcon.playing, "AutoHush: music is playing", "Playing"),
        (.pausedByMonitor, .pausedForApp, "AutoHush: music paused", "Paused — another app is playing"),
        (.musicIdle, .noMusic, "AutoHush: no music playing", "Not playing"),
        (.playingElsewhere, .elsewhere, "AutoHush: music is playing on another device", "Playing on another device"),
    ])
    func playbackState(state: PlaybackState, icon: MenuBarIcon, label: String, line: String) {
        #expect(state.presentation() == StatePresentation(icon: icon, label: label, line: line))
    }

    @Test("describes playing apps in natural language")
    func describePlaying() {
        #expect(PlaybackState.describePlaying(["VLC"]) == "VLC is playing")
        #expect(PlaybackState.describePlaying(["A", "B"]) == "A and B are playing")
        #expect(PlaybackState.describePlaying(["A", "B", "C", "D"]) == "A and 3 other apps are playing")
    }

    @Test("a pause names the apps that caused it")
    func pauseNamesApps() {
        #expect(PlaybackState.pausedByMonitor.presentation(playing: ["VLC"]).line == "Paused — VLC is playing")
    }

    @Test("once ready, the menu follows the playback state rather than the health")
    func readyHasNoLookOfItsOwn() {
        #expect(AppHealthState.ready.presentation == nil)
    }

    @Test("an unknown playback state looks like starting up")
    func unknownPlaybackState() {
        #expect(PlaybackState.unknown.presentation() == AppHealthState.starting.presentation)
    }

    @Test("each health state has its icon, label and status line; problems show their message", arguments: [
        (AppHealthState.starting, MenuBarIcon.starting, "AutoHush: starting", "Starting services"),
        (.needsPlayer("Choose a music player"), .attention, "AutoHush: no music player chosen", "Choose a music player"),
        (.degraded("Jukebox is not running"), .attention, "AutoHush: degraded", "Jukebox is not running"),
        (.needsPermission(.automation(player: "Jukebox")), .attention,
         "AutoHush: needs permission", "Grant Automation access to control Jukebox"),
        (.needsPermission(.accessibility(player: "Jukebox")), .attention,
         "AutoHush: needs permission", "Grant Accessibility access to control Jukebox"),
        (.failed("Monitor failed hard"), .attention, "AutoHush: failed", "Monitor failed hard"),
    ])
    func healthState(state: AppHealthState, icon: MenuBarIcon, label: String, line: String) {
        #expect(state.presentation == StatePresentation(icon: icon, label: label, line: line))
    }

    // MARK: - Menu text for the engine's choices

    @Test("each permission names what to grant", arguments: [
        (Permission.automation(player: "Jukebox"), "Allow Jukebox Automation Access…"),
        (Permission.accessibility(player: "Jukebox"), "Allow Accessibility Access…"),
        (.systemAudioRecording, "Allow Audio Recording Access…"),
    ])
    func grantTitle(permission: Permission, title: String) {
        #expect(permission.grantTitle == title)
    }

    @Test("snooze end times are described relative to today, with their preposition")
    func describeEnd() {
        let calendar = TestDates.calendar
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let now = TestDates.date(2, 12)

        #expect(AutoPauseSnooze.describeEnd(TestDates.date(2, 15, 30), now: now, calendar: calendar)
            == "until \(TestDates.date(2, 15, 30).formatted(style))")
        #expect(AutoPauseSnooze.describeEnd(TestDates.date(3, 8), now: now, calendar: calendar)
            == "until tomorrow \(TestDates.date(3, 8).formatted(style))")
    }
}
