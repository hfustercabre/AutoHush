import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit

@Suite("StatusPresentation")
struct StatusPresentationTests {

    // MARK: - States

    @Test("each playback state has its symbol, label and status line", arguments: [
        (PlaybackState.musicPlaying, "play.circle.fill", "AutoHush: music is playing", "Music is playing"),
        (.pausedByMonitor, "pause.circle.fill", "AutoHush: music paused", "Music paused — another app is playing"),
        (.musicIdle, "music.note", "AutoHush: no music playing", "No music playing"),
        (.playingElsewhere, "hifispeaker.fill", "AutoHush: music is playing on another device",
         "Music is playing on another device"),
    ])
    func playbackState(state: PlaybackState, symbol: String, label: String, line: String) {
        #expect(state.presentation == StatePresentation(symbol: symbol, label: label, line: line))
    }

    @Test("an unknown playback state looks like starting up")
    func unknownPlaybackState() {
        #expect(PlaybackState.unknown.presentation == AppHealthState.starting.presentation)
    }

    @Test("each health state has its symbol, label and status line; problems show their message", arguments: [
        (AppHealthState.starting, "arrow.triangle.2.circlepath", "AutoHush: starting", "Starting services"),
        (.ready, "speaker.wave.2.fill", "AutoHush: monitoring", "Monitoring media playback"),
        (.degraded("Spotify is not running"), "exclamationmark.triangle.fill", "AutoHush: degraded",
         "Spotify is not running"),
        (.needsPermission("Grant Automation access to control Spotify"), "lock.trianglebadge.exclamationmark.fill",
         "AutoHush: needs permission", "Grant Automation access to control Spotify"),
        (.failed("Monitor failed hard"), "speaker.slash.fill", "AutoHush: failed", "Monitor failed hard"),
    ])
    func healthState(state: AppHealthState, symbol: String, label: String, line: String) {
        #expect(state.presentation == StatePresentation(symbol: symbol, label: label, line: line))
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
