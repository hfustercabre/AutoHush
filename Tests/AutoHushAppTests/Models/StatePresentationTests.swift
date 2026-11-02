import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("StatePresentation")
struct StatePresentationTests {

    // MARK: - States

    @Test("each playback state has its icon, label and status line", arguments: [
        (PlaybackState.musicPlaying, MenuBarIcon.playing, "AutoHush: your player is playing", "Playing"),
        (.pausedByMonitor, .pausedForApp, "AutoHush: playback paused", "Paused — another app is playing"),
        (.musicIdle, .noMusic, "AutoHush: nothing is playing", "Not playing"),
        (.playingSilently, .noMusic, "AutoHush: your player is playing silently", "Playing silently"),
        (.playingElsewhere, .elsewhere, "AutoHush: your player is playing on another device", "Playing on another device"),
    ])
    func playbackState(state: PlaybackState, icon: MenuBarIcon, label: String, line: String) {
        let presentation = state.presentation()
        #expect(presentation.icon == icon && presentation.label == label && presentation.line == line)
    }

    @Test("the lines that surprise say why in their help tag and VoiceOver hint; the others say nothing more", arguments: [
        (PlaybackState.playingSilently, Optional("Nothing of it is heard, so AutoHush doesn’t pause it.")),
        (.playingElsewhere, "AutoHush pauses only what plays on this Mac."),
        (.musicPlaying, nil),
        (.pausedByMonitor, nil),
        (.musicIdle, nil),
        (.pauseFailed, nil),
    ])
    func lineHelp(state: PlaybackState, help: String?) {
        #expect(state.presentation().help == help)
    }

    @Test("a muted player's line says why it's muted, as it can only be muted or its pause didn't take; one held for a check, until when")
    func mutedAndHeldHelp() {
        #expect(StatePresentation.muted(playing: ["Safari"], onlyMutes: true).help
            == "It can’t be paused, so it’s muted until the other apps stop.")
        #expect(StatePresentation.muted(playing: ["Safari"], onlyMutes: false).help
            == "It played on after its pause, so it’s muted until the other apps stop.")
        #expect(StatePresentation.heldForCheck.help == "Kept paused until Add an App’s check ends.")
    }

    @Test("describes playing apps in natural language")
    func describePlaying() {
        #expect(PlaybackState.describePlaying(["Viewer"]) == "Viewer is playing")
        #expect(PlaybackState.describePlaying(["A", "B"]) == "A and B are playing")
        #expect(PlaybackState.describePlaying(["A", "B", "C", "D"]) == "A and 3 other apps are playing")
        // One app with its microphone on that made no sound yet (Pause for the microphone).
        #expect(PlaybackState.describePlaying(["Zoom"], microphone: true) == "Zoom is using the microphone")
        #expect(PlaybackState.describePlaying(["Zoom", "Safari"], microphone: true) == "Zoom and Safari are playing")
    }

    @Test("once ready, the menu follows the playback state rather than the health")
    func readyHasNoLookOfItsOwn() {
        #expect(AppHealthState.ready.presentation == nil)
    }

    @Test("an unknown playback state looks like starting up")
    func unknownPlaybackState() {
        #expect(PlaybackState.unknown.presentation() == AppHealthState.starting.presentation)
    }

    @Test("each health state has its icon, label and status line; problems show their message, which VoiceOver says too", arguments: [
        (AppHealthState.starting, MenuBarIcon.starting, "AutoHush: starting", "Starting…"),
        (.needsPlayer("Choose a media player"), .attention, "AutoHush: Choose a media player", "Choose a media player"),
        (.playerClosed("Jukebox isn’t running"), .noMusic, "AutoHush: Jukebox isn’t running", "Jukebox isn’t running"), // calm: nothing to do
        (.retrying("Jukebox isn’t responding"), .attention, "AutoHush: Jukebox isn’t responding", "Jukebox isn’t responding"),
        (.needsPermission(.automation(player: "Jukebox")), .attention,
         "AutoHush: Needs Automation access", "Needs Automation access"),
        (.needsPermission(.accessibility(player: "Jukebox")), .attention,
         "AutoHush: Needs Accessibility access", "Needs Accessibility access"),
        (.failed("Monitor failed hard"), .attention, "AutoHush: Monitor failed hard", "Monitor failed hard"),
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
