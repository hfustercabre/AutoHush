import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppStatus")
struct AppStatusTests {
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
    private let viewer = AudioSource(id: "org.example.viewer", name: "Viewer")
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

    @Test("a given-up resume says “Couldn’t resume”, its alert why; not while a pause holds or fails")
    func resumeGivenUp() {
        var status = ready(.musicIdle)
        status.resumeError = ControlError(MusicPlayerError.playerNotResponding, player: "Jukebox")
        #expect(status.showsResumeFailure && status.needsAttention) // orange, as Couldn't pause
        #expect(status.statusLine == "Couldn’t resume — Jukebox didn’t answer")
        #expect(status.controlErrorAlert()?.title == "Couldn’t Resume Jukebox")
        #expect(status.controlErrorAlert()?.message.hasPrefix("Jukebox isn’t responding.") == true)
        // Its alert's button follows its own error, not a pause's (the apps
        // stopping cleared that): Now Playing hidden offers the pane.
        status.resumeError = ControlError(MusicPlayerError.playerCommandFailed(.nowPlayingHidden), player: "Jukebox")
        #expect(status.controlError == nil && status.alertError?.opensMenuBarSettings == true)
        status.playback = .pausedByMonitor // paused again for another app
        status.setActiveSources([safari])
        #expect(!status.showsResumeFailure && !status.needsAttention)
        #expect(status.statusLine == "Paused — Safari is playing")
    }

    @Test("a player muted instead of paused says “Muted”, with Unmute, while another app plays; one held for a check says so")
    func muted() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([chrome])
        status.playerOptions[0].pausesByMuting = true
        #expect(status.statusLine == "Muted — Google Chrome is playing")
        #expect(status.icon == .pausedForApp && status.offersUnmute)
        status.playback = .musicPlaying
        #expect(!status.offersUnmute)
        #expect(AppStatus.unmuteTitle == "Unmute")

        // Kept paused while Add an App checks an app, also when nothing plays in its gaps.
        status.playerOptions[0].pausesByMuting = false
        status.playerHeldForCheck = true
        status.playback = .pausedByMonitor
        status.setActiveSources([])
        #expect(status.statusLine == "Paused while a check runs" && status.icon == .pausedForApp)
        status.playback = .musicIdle
        #expect(status.statusLine == "Not playing")
    }

    @Test("a player muted in place of the pause (it kept starting again by itself) says “Muted”, with Unmute (the user, 2026-10-25); Paused once the mute is over")
    func mutedInstead() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([chrome])
        status.playerMutedInstead = true
        #expect(status.statusLine == "Muted — Google Chrome is playing")
        #expect(status.icon == .pausedForApp && status.offersUnmute)
        status.playerMutedInstead = false
        #expect(status.statusLine == "Paused — Google Chrome is playing")
        #expect(!status.offersUnmute)
    }

    @Test("while the player is muted in place of the pause, the apps that interrupt it say “Mutes your player”; “Pauses” again once it's over")
    func mutesNow() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([chrome])
        #expect(!status.mutesNow)
        status.playerMutedInstead = true
        #expect(status.mutesNow && SourceText.subtitle(isIgnored: false, mutes: status.mutesNow) == "Mutes your player")
        status.playback = .musicIdle // the mute's flag alone, once AutoHush no longer holds a pause
        #expect(!status.mutesNow && SourceText.subtitle(isIgnored: false, mutes: status.mutesNow) == "Pauses your player")
        status.playerMutedInstead = false
        status.playerOptions[0].pausesByMuting = true // one that can only be muted, whatever it does
        #expect(status.mutesNow)
        #expect(SourceText.subtitle(isIgnored: true, mutes: true) == IgnoredText.label) // ignored, it says only that
    }

    @Test("a given-up resume says so whatever Auto-Pause is, as a player that needs reopening does: its line with Try Again, never “Auto-Pause is off”")
    func resumeGivenUpWithAutoPauseOff() {
        for autoPause in [AppStatus.AutoPause.off, .snoozed("until 15:30")] {
            var status = ready(.musicIdle)
            status.resumeError = ControlError(MusicPlayerError.playerNotResponding, player: "Jukebox")
            status.autoPause = autoPause
            #expect(status.showsResumeFailure && status.needsAttention)
            #expect(status.statusLine == "Couldn’t resume — Jukebox didn’t answer")
            #expect(status.icon == .attention && status.dimsIcon)
            #expect(status.iconAccessibilityLabel == "AutoHush: Couldn’t resume — Jukebox didn’t answer")
            status.resumeError = nil
            #expect(status.statusLine.hasPrefix("Auto-Pause is off"))
        }
    }

    @Test("a player opened without what it needs says so, with the attention icon, whatever Auto-Pause is")
    func needsReopen() {
        var status = ready(.musicPlaying)
        status.autoPause = .off
        status.playerNeedsReopen = true
        #expect(status.statusLine == "Jukebox needs reopening")
        #expect(status.icon == .attention)
        #expect(status.needsAttention)
        status.playerNeedsReopen = false
        #expect(status.statusLine == "Auto-Pause is off")
        #expect(AppStatus.reopenPlayerTitle == "Reopen") // the line above names the player
    }

    @Test("a pause that failed while another app plays says so, in orange with the attention icon")
    func pauseFailed() {
        var status = ready(.pauseFailed)
        status.setActiveSources([safari])
        #expect(status.statusLine == "Couldn’t pause — Safari is playing")
        #expect(status.icon == .attention)
        #expect(status.needsAttention)
        status.autoPause = .off
        #expect(!status.needsAttention) // auto-pause off says so instead
    }

    @Test("the info button's alert says what failed, then why in words, and as the log has it unless AutoHush speaks English")
    func controlErrorAlert() {
        var status = ready(.pauseFailed)
        #expect(status.controlErrorAlert() == nil) // nothing to tell
        let error = ControlError(MusicPlayerError.playerCommandFailed(.pressIgnored), player: "Jukebox")
        status.controlError = error
        #expect(status.controlErrorAlert()?.title == "Couldn’t Pause Jukebox")
        #expect(status.controlErrorAlert(inEnglish: false)?.message == "\(error.text)\n\n\(error.detail)")
        #expect(status.controlErrorAlert(inEnglish: true)?.message == error.text) // once is enough
        // An error AutoHush has no words of its own for says the same in both: once, in any language.
        status.controlError = ControlError(StubError.failed, player: "Jukebox")
        #expect(status.controlError?.ownDetail == nil)
        #expect(status.controlErrorAlert(inEnglish: false)?.message == "stub failed")
        status.controlError = ControlError(MusicPlayerError.stillLearning, player: "Jukebox")
        #expect(status.controlErrorAlert(inEnglish: false)?.message == status.controlError?.text)
        #expect(error.ownDetail == error.detail)
        status.setHealth(.retrying("Can’t control Jukebox right now"))
        #expect(status.controlErrorAlert()?.title == "Can’t Control Jukebox")
    }

    @Test("starts in the starting state with nothing to fix")
    func initialState() {
        let status = AppStatus()
        #expect(status.health == .starting)
        #expect(status.statusLine == "Starting services")
        #expect(status.icon == .starting)
        #expect(status.warning == nil && !status.canRetry && !status.dimsIcon)
    }

    @Test("when ready, icon and status line follow playback, as the playback state presents itself")
    func readyFollowsPlayback() {
        let status = ready(.playingElsewhere)
        let presentation = PlaybackState.playingElsewhere.presentation()
        #expect(status.icon == presentation.icon)
        #expect(status.statusLine == presentation.line)
    }

    @Test("the card is titled with the chosen player, or AutoHush while none is chosen")
    func cardTitle() {
        #expect(ready().cardTitle == "Jukebox")
        #expect(AppStatus().cardTitle == "AutoHush")
    }

    @Test("a pause names the apps that caused it")
    func pauseNamesApps() {
        var status = ready(.pausedByMonitor)
        status.setActiveSources([viewer])
        #expect(status.statusLine == "Paused — Viewer is playing")
        status.setActiveSources([viewer, chrome])
        #expect(status.statusLine == "Paused — Google Chrome and Viewer are playing")
        status.setActiveSources([viewer, chrome, safari])
        #expect(status.statusLine == "Paused — Google Chrome and 2 other apps are playing")
        status.setActiveSources([])
        #expect(status.statusLine == "Paused — another app is playing")
    }

    @Test("an app that stops playing is listed as recently played, the most recent first")
    func recentlyPlayed() {
        var status = ready()
        let start = Date()
        status.setActiveSources([viewer, chrome], now: start)
        #expect(status.recentSources(at: start).isEmpty)
        status.setActiveSources([chrome], now: start + 10)
        status.setActiveSources([], now: start + 20)
        #expect(status.recentSources(at: start + 30) == [chrome, viewer])
    }

    /// Viewer and Chrome played from `start`; Viewer stopped 10 s later, Chrome
    /// 20 s later, and Viewer plays again at 40 s.
    private func viewerPlaysAgain(from start: Date) -> AppStatus {
        var status = ready()
        status.setActiveSources([viewer, chrome], now: start)
        status.setActiveSources([chrome], now: start + 10)
        status.setActiveSources([], now: start + 20)
        status.setActiveSources([viewer], now: start + 40)
        return status
    }

    @Test("an app recently played is no longer listed so once it plays again")
    func recentlyPlayedUntilPlayingAgain() {
        let start = Date()
        let status = viewerPlaysAgain(from: start)
        #expect(status.recentSources(at: start + 50) == [chrome]) // playing again: under Playing Now only
    }

    @Test("an app playing when monitoring stops is listed as recently played too")
    func recentlyPlayedAsMonitoringStops() {
        let start = Date()
        var status = viewerPlaysAgain(from: start)
        // Another player chosen: nothing is monitored until it starts.
        status.setHealth(.starting, now: start + 60)
        #expect(status.activeSources.isEmpty)
        #expect(status.recentSources(at: start + 70) == [viewer, chrome])
    }

    @Test("an app stays listed as recently played for 30 minutes")
    func recentlyPlayedFor30Minutes() {
        let start = Date()
        var status = viewerPlaysAgain(from: start)
        status.setHealth(.starting, now: start + 60) // Viewer stops too
        #expect(status.recentSources(at: start + 60 + 29 * 60) == [viewer, chrome])
        #expect(status.recentSources(at: start + 60 + 30 * 60).isEmpty)
    }

    @Test("Recently Played lists the four that stopped last")
    func recentlyPlayedAtMost4() {
        var status = ready()
        let start = Date()
        let apps = (1...6).map { AudioSource(id: "com.example.app\($0)", name: "App \($0)") }
        for (index, app) in apps.enumerated() {
            status.setActiveSources([app], now: start + Double(index))
        }
        status.setActiveSources([], now: start + 10)
        #expect(status.recentSources(at: start + 11).map(\.name) == ["App 6", "App 5", "App 4", "App 3"])
        status.chosenPlayerID = apps[5].id // the chosen player takes no place among the four
        #expect(status.recentSources(at: start + 11).map(\.name) == ["App 5", "App 4", "App 3", "App 2"])
    }

    @Test("ignored apps are listed but never named as the cause of a pause")
    func ignoredAppsAreNotCauses() {
        var status = ready(.pausedByMonitor)
        status.ignoredApps = [viewer]
        status.setActiveSources([viewer, chrome])
        #expect(status.activeSources == [chrome, viewer])
        #expect(status.pausingSources == [chrome])
        #expect(status.isIgnored(viewer.id))
        #expect(status.statusLine == "Paused — Google Chrome is playing")
    }

    @Test("auto-pause off replaces the status line and dims the icon, which VoiceOver says, as the dimming doesn't")
    func autoPauseOff() {
        var status = ready(.musicPlaying)
        status.autoPause = .off
        #expect(status.statusLine == "Auto-Pause is off")
        #expect(status.dimsIcon && status.iconAccessibilityLabel == "AutoHush: Auto-Pause is off")
        status.autoPause = .snoozed("until 15:30")
        #expect(status.statusLine == "Auto-Pause is off until 15:30")
        #expect(status.dimsIcon && status.iconAccessibilityLabel == "AutoHush: Auto-Pause is off until 15:30")
        status.autoPause = .on
        #expect(!status.dimsIcon && status.iconAccessibilityLabel == "AutoHush: your player is playing")
    }

    @Test("while an update waits, the icon shows it, and VoiceOver says so after the icon's label")
    func updateBadge() {
        var status = ready(.musicPlaying)
        let label = status.iconAccessibilityLabel
        #expect(!status.iconShowsUpdate)
        let release = AppRelease.github("0.3.0", diskImage: false)
        for state in [UpdateOffer.State.available, .downloaded, .installing] {
            status.updateOffer = UpdateOffer(release: release, state: state)
            #expect(status.iconShowsUpdate)
            #expect(status.iconAccessibilityLabel == "\(label), update available")
        }
        status.updateOffer = nil
        #expect(!status.iconShowsUpdate)
        #expect(status.iconAccessibilityLabel == label)
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
        status.setHealth(.playerClosed("Jukebox isn’t running"))
        #expect(status.statusLine == "Jukebox isn’t running")
        #expect(!status.dimsIcon)
    }

    @Test("a closed player clears sources and needs nothing: it starts on by itself once it opens, so no Try Again, and the icon is as with no music")
    func closedPlayerIsCalm() {
        var status = ready(.musicPlaying)
        status.setActiveSources([chrome])
        status.setHealth(.playerClosed("Jukebox isn’t running"))
        #expect(status.activeSources.isEmpty)
        #expect(status.icon == .noMusic && !status.needsAttention)
        #expect(!status.canRetry)
        #expect(status.warning == nil)
    }

    @Test("Retry is offered only after a failed start nothing announces the end of; every problem needs attention, a closed player none", arguments: [
        (AppHealthState.retrying("Jukebox isn’t responding"), true), (.failed("Monitor failed hard"), true),
        (.degraded("Jukebox isn’t installed"), false), (.needsPermission(.automation(player: "Jukebox")), false),
        (.needsPlayer("Choose a media player"), false), (.playerClosed("Jukebox isn’t running"), false), (.starting, false), (.ready, false),
    ])
    func retryOffered(health: AppHealthState, offered: Bool) {
        var status = AppStatus()
        status.setHealth(health)
        #expect(status.canRetry == offered)
        #expect(status.needsAttention == (health != .starting && health != .ready && health != .playerClosed("Jukebox isn’t running")))
    }

    @Test("waiting for a music player to be chosen needs attention, but no Retry or warning")
    func waitingForPlayer() {
        var status = AppStatus()
        status.setHealth(.needsPlayer("Choose a media player"))
        #expect(status.icon == .attention)
        #expect(status.statusLine == "Choose a media player")
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

    @Test("once the user went to allow audio recording, its warning reopens AutoHush; other warnings ask as usual")
    func audioAccessWarningOffersReopen() {
        var status = ready()
        status.detection = .unavailable
        #expect(status.warning == .systemAudioRecording && !status.offersReopen)
        status.awaitsReopenForAudioRecording = true
        #expect(status.offersReopen)
        status.setHealth(.needsPermission(.automation(player: "Jukebox")))
        #expect(status.warning == .automation(player: "Jukebox") && !status.offersReopen)
    }

    @Test("the card's Controls row shows for a chosen player that learns, learned or not, permission or not")
    func controlsRow() {
        var status = ready()
        #expect(!status.canLearnControlsAgain) // a player that learns nothing
        for learning in [LearningStatus.learning(hasPlayed: false), .learning(hasPlayed: true), .relearning, .learned] {
            status.learning = learning
            #expect(status.canLearnControlsAgain)
        }
        status.setHealth(.needsPermission(.accessibility(player: "Jukebox")))
        #expect(status.canLearnControlsAgain)
        status.chosenPlayerID = nil // deleted: nothing to learn
        #expect(!status.canLearnControlsAgain)
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
        status.setHealth(.playerClosed("Jukebox isn’t running"))
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
