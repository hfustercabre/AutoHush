import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("StatusPresentation")
struct StatusPresentationTests {

    // MARK: - States

    @Test("each playback state has its icon, label and status line", arguments: [
        (PlaybackState.musicPlaying, MenuBarIcon.playing, "AutoHush: music is playing", "Music is playing"),
        (.pausedByMonitor, .pausedForApp, "AutoHush: music paused", "Music paused — another app is playing"),
        (.musicIdle, .noMusic, "AutoHush: no music playing", "No music playing"),
        (.playingElsewhere, .elsewhere, "AutoHush: music is playing on another device",
         "Music is playing on another device"),
    ])
    func playbackState(state: PlaybackState, icon: MenuBarIcon, label: String, line: String) {
        #expect(state.presentation == StatePresentation(icon: icon, label: label, line: line))
    }

    @Test("an unknown playback state looks like starting up")
    func unknownPlaybackState() {
        #expect(PlaybackState.unknown.presentation == AppHealthState.starting.presentation)
    }

    @Test("each health state has its icon, label and status line; problems show their message", arguments: [
        (AppHealthState.starting, MenuBarIcon.starting, "AutoHush: starting", "Starting services"),
        (.ready, .playing, "AutoHush: monitoring", "Monitoring media playback"),
        (.degraded("Spotify is not running"), .attention, "AutoHush: degraded", "Spotify is not running"),
        (.needsPermission("Grant Automation access to control Spotify"), .attention,
         "AutoHush: needs permission", "Grant Automation access to control Spotify"),
        (.failed("Monitor failed hard"), .attention, "AutoHush: failed", "Monitor failed hard"),
    ])
    func healthState(state: AppHealthState, icon: MenuBarIcon, label: String, line: String) {
        #expect(state.presentation == StatePresentation(icon: icon, label: label, line: line))
    }

    // MARK: - Menu text for the engine's choices

    @Test("each permission names what to grant", arguments: [
        (Permission.automation(player: "Spotify"), "Allow Spotify Automation Access…"),
        (.systemAudioRecording, "Allow Audio Recording Access…"),
    ])
    func grantTitle(permission: Permission, title: String) {
        #expect(permission.grantTitle == title)
    }

    @Test("snooze end times are described relative to today")
    func describeEnd() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        let now = date(2, 12)

        #expect(AutoPauseSnooze.describeEnd(date(2, 15, 30), now: now, calendar: calendar)
            == date(2, 15, 30).formatted(style))
        #expect(AutoPauseSnooze.describeEnd(date(3, 8), now: now, calendar: calendar)
            == "tomorrow \(date(3, 8).formatted(style))")
        #expect(AutoPauseSnooze.describeEnd(date(5, 8), now: now, calendar: calendar).hasSuffix(date(5, 8).formatted(style)))
    }
}
