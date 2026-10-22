import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import CheckedPlayers

@Suite("DiagnosticsReport")
struct DiagnosticsReportTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Jukebox chosen and installed, ready, the music paused for Google Chrome.
    private func workingStatus() -> AppStatus {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.setHealth(.ready)
        status.detection = .audioLevel
        status.playback = .pausedByMonitor
        status.setActiveSources([AudioSource(id: "com.google.Chrome", name: "Google Chrome")])
        status.ignoredApps = [AudioSource(id: "org.videolan.vlc", name: "VLC")]
        return status
    }

    private func facts(_ change: (inout DiagnosticsFacts) -> Void = { _ in }) -> DiagnosticsFacts {
        var facts = DiagnosticsFacts(
            playerVersion: "2.1", playerCanFade: true,
            playerPermission: .automation(player: "Jukebox"), playerPermissionGranted: true,
            audioRecording: .granted, notificationsOff: false, detectionMethod: .audioLevels,
            appVersion: "0.6.1 (19)", launchAtLogin: true, checksForUpdates: true, automaticUpdates: .install,
            lastUpdateCheck: now.addingTimeInterval(-3600), macOS: "27.0.1 (26A434)", processor: "Apple silicon", now: now
        )
        change(&facts)
        return facts
    }

    private let chrome = ActiveAudioReport.Entry(id: "com.google.Chrome", name: "Google Chrome", state: .playing, evidence: .level(0.1))

    @Test("the report says how AutoHush is doing, lists the apps with sound, then each section, label by label")
    func fullReport() {
        let snapshot = DiagnosticsReport.snapshot(activeAudio: [chrome], status: workingStatus(), facts: facts())
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2))) // as the Mac's region writes it
        #expect(snapshot.text == """
            Working normally — Jukebox · Paused — Google Chrome is playing

            Apps with Sound
            Google Chrome (com.google.Chrome) — playing (-20 dBFS)

            Media Player
            Player: Jukebox 2.1
            State: Paused by AutoHush
            Fades: Yes

            Behavior
            Pause playback after: \(half) s
            Pause for the microphone: Off
            Pause on disconnect: Off
            Resume playback: On
            Resume playback after: 2 s
            Stay paused after calls: Off
            Fade out before pausing: 1 s
            Fade in when resuming: 2 s
            Level the volume: Off

            Detection
            Detecting by: Audio levels
            AntiDot mode: Off
            Silence threshold: -60 dB

            Permissions
            Audio Recording: Allowed
            Automation for Jukebox: Allowed
            Notifications: Allowed

            AutoHush
            Version: 0.6.1 (19)
            Auto-Pause: On
            Ignored apps: VLC
            Launch at login: On
            Keep icon next to system icons: Off
            Updates: Install it automatically
            Last checked: 1 hour ago

            This Mac
            macOS: 27.0.1 (26A434)
            Processor: Apple silicon
            """)
    }

    @Test("the tab gets each app with its icon and judgement, a summary for each part, and the sections in order")
    func snapshot() {
        let activeAudio = [chrome, ActiveAudioReport.Entry(id: "org.videolan.vlc", state: .silent, isIgnored: true)]
        let snapshot = DiagnosticsReport.snapshot(
            activeAudio: activeAudio, status: workingStatus(), facts: facts(),
            bundlePath: { $0 == "com.google.Chrome" ? "/Applications/Google Chrome.app" : nil }
        )
        #expect(snapshot.overview == .init(kind: .working, title: "Working normally",
                                           detail: "Jukebox · Paused — Google Chrome is playing"))
        #expect(snapshot.apps == [
            .init(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app",
                  judgement: "Playing", evidence: "-20 dBFS"),
            .init(id: "org.videolan.vlc", name: "org.videolan.vlc", bundlePath: nil,
                  judgement: "Output open, silent, ignored", evidence: nil),
        ])
        #expect(snapshot.appsSummary == "Google Chrome, org.videolan.vlc")
        #expect(snapshot.sections.map(\.kind) == [.player, .behavior, .detection, .permissions, .autoHush, .mac])
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2))) // as the Mac's region writes it
        #expect(snapshot.sections.map(\.summary) == [
            "Jukebox · Paused by AutoHush", "Pauses after \(half) s, resumes after 2 s", "Audio levels", "All allowed",
            "Version 0.6.1 (19)", "macOS 27.0.1 (26A434)",
        ])
    }

    @Test("the card on top: working, needs attention, auto-pause off, starting (until the player's state is known too)")
    func overview() {
        var attention = workingStatus()
        attention.setHealth(.needsPermission(.automation(player: "Jukebox")))
        var snoozed = workingStatus()
        snoozed.autoPause = .snoozed("until 15:30")
        var unknownState = workingStatus()
        unknownState.playback = .unknown
        let kinds = [workingStatus(), attention, snoozed, AppStatus(), unknownState].map {
            DiagnosticsReport.snapshot(activeAudio: [], status: $0, facts: facts()).overview
        }
        #expect(kinds.map(\.kind) == [.working, .attention, .off, .starting, .starting])
        #expect(kinds[1].detail == "Needs Automation access")
        #expect(kinds[2].title == "Auto-Pause is off until 15:30")
    }

    @Test("the music player's part says whether its words were read, and its last error in words and in English")
    func playerWordsAndLastError() {
        var status = workingStatus()
        status.controlError = ControlError(MusicPlayerError.playerCommandFailed(.menuItemNotFound), player: "Jukebox")
        let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts { $0.playerWordsRead = false })
        let rows = snapshot.sections.first { $0.kind == .player }?.rows ?? []
        #expect(rows.contains(DiagnosticsSnapshot.Row(label: "Play/Pause words read", value: "No", mark: .problem)))
        #expect(rows.contains(DiagnosticsSnapshot.Row(
            label: "Last error",
            value: "AutoHush can’t find Play/Pause in Jukebox’s menus.\nControlling the media player failed: its Play/Pause menu item wasn’t found.",
            mark: .problem)))

        let plain = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts())
        let plainRows = plain.sections.first { $0.kind == .player }?.rows.map(\.label) ?? []
        #expect(!plainRows.contains("Play/Pause words read")) // a player that needs no words
        #expect(!plainRows.contains("Last error"))
    }

    @Test("permissions: allowed, refused, not asked yet, unknown, not needed in AntiDot mode, and not checked yet, each with its mark (Allow… beside a missing one); Audio Recording once")
    func permissions() throws {
        func rows(_ change: (inout DiagnosticsFacts) -> Void) throws -> [DiagnosticsSnapshot.Row] {
            let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts(change))
            return try #require(snapshot.sections.first { $0.kind == .permissions }).rows
        }
        #expect(try rows { _ in } == [
            .init(label: "Audio Recording", value: "Allowed", mark: .ok),
            .init(label: "Automation for Jukebox", value: "Allowed", mark: .ok),
            .init(label: "Notifications", value: "Allowed", mark: .ok),
        ])
        #expect(try rows {
            $0.audioRecording = .denied
            $0.playerPermission = .accessibility(player: "Jukebox")
            $0.playerPermissionGranted = false
            $0.notificationsOff = true
        } == [
            .init(label: "Audio Recording", value: "Not allowed", mark: .problem, fix: .allow(.systemAudioRecording)),
            .init(label: "Accessibility for Jukebox", value: "Not allowed", mark: .problem, fix: .allow(.accessibility(player: "Jukebox"))),
            .init(label: "Notifications", value: "Off", mark: .neutral),
        ])
        #expect(try rows {
            $0.audioRecording = .notDetermined
            $0.detectionMethod = .playbackSignals
            $0.playerPermissionGranted = nil
        }.map(\.value) == ["Not needed in AntiDot mode", "Not checked yet", "Allowed"])
        // Measuring audio levels: macOS hasn't asked yet, or can't tell.
        #expect(try rows { $0.audioRecording = .notDetermined }.first == .init(label: "Audio Recording", value: "Not asked yet", mark: .problem, fix: .allow(.systemAudioRecording)))
        #expect(try rows { $0.audioRecording = nil }.first == .init(label: "Audio Recording", value: "Unknown", mark: .neutral))
        // An app muted instead of paused needs Audio Recording to control it too: one row, which can't disagree with itself.
        #expect(try rows {
            $0.audioRecording = nil
            $0.playerPermission = .systemAudioRecording
        } == [
            .init(label: "Audio Recording", value: "Unknown", mark: .neutral),
            .init(label: "Notifications", value: "Allowed", mark: .ok),
        ])

        let refused = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts { $0.audioRecording = .denied })
        #expect(refused.sections.first { $0.kind == .permissions }?.summary == "Something’s missing")
    }

    /// The report while nothing plays, no player is chosen and nothing is
    /// ignored, with no update checks, leveling on and staying paused after
    /// calls, `detection` detected by `method`; resuming as `resumes` says.
    private func quietReport(_ detection: DetectionMode, _ method: DetectionMethod,
                             resumes: Bool = true) -> DiagnosticsSnapshot {
        var status = AppStatus()
        status.setHealth(.ready)
        status.detection = detection
        return DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts {
            $0.detectionMethod = method
            $0.playerPermission = nil
            $0.checksForUpdates = false
            $0.lastUpdateCheck = nil
            $0.timings.levelsMusic = true
            $0.timings.staysPausedAfterCalls = true
            $0.timings.resumesPlayback = resumes
        })
    }

    @Test("Behavior says what resuming uses only while it resumes: its wait, the fade-in, leveling (off whatever its switch) and its limits; Stay paused after calls as set",
          arguments: [true, false])
    func saysResumePlayback(resumes: Bool) {
        let snapshot = quietReport(.audioLevel, .audioLevels, resumes: resumes)
        let text = snapshot.text
        if resumes {
            #expect(text.contains("Resume playback: On\nResume playback after: 2 s\nStay paused after calls: On\nFade out before pausing: 1 s\nFade in when resuming: 2 s\nLevel the volume: On\nLower by at most: 10 dB\nOnly when quieter by: 2 dB\n"))
        } else {
            #expect(text.contains("Resume playback: Off\nStay paused after calls: On\nFade out before pausing: 1 s\nLevel the volume: Off\n\nDetection"))
            #expect(!text.contains("Resume playback after") && !text.contains("Fade in") && !text.contains("Lower by at most"))
        }
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2)))
        let summary = snapshot.sections.first { $0.kind == .behavior }?.summary
        #expect(summary == (resumes ? "Pauses after \(half) s, resumes after 2 s" : "Pauses after \(half) s, never resumes"))
    }

    @Test("Behavior leaves out the fade lengths while the fades are off or the player can't fade", arguments: [true, false])
    func saysNoFadeLengths(canFade: Bool) {
        var status = workingStatus()
        status.playback = .musicIdle
        let text = DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts {
            $0.playerCanFade = canFade
            $0.timings.fadesEnabled = !canFade // off when the player could fade
        }).text
        #expect(!text.contains("Fade out before pausing") && !text.contains("Fade in when resuming"))
        #expect(text.contains("Stay paused after calls: Off\nLevel the volume: Off"))
    }

    @Test("says when nothing plays")
    func saysNothingPlays() {
        let snapshot = quietReport(.playbackSignals, .playbackSignals)
        #expect(snapshot.appsSummary == "None")
        #expect(snapshot.text.contains("Apps with Sound\nNo other app is playing sound right now."))
    }

    @Test("says when no player is chosen")
    func saysNoPlayerChosen() {
        #expect(quietReport(.playbackSignals, .playbackSignals).text.contains("Player: None chosen"))
    }

    @Test("says when nothing is ignored")
    func saysNothingIgnored() {
        #expect(quietReport(.playbackSignals, .playbackSignals).text.contains("Ignored apps: None"))
    }

    @Test("says when update checks are off and none was made")
    func saysNoUpdateChecks() {
        #expect(quietReport(.playbackSignals, .playbackSignals).text.contains("Updates: Automatic checks off\nLast checked: Never"))
    }

    @Test("says when AntiDot mode is on, with no silence threshold, and leveling off with it")
    func saysAntiDotOn() {
        let snapshot = quietReport(.playbackSignals, .playbackSignals)
        #expect(snapshot.text.contains("Detecting by: What apps tell macOS\nAntiDot mode: On"))
        #expect(!snapshot.text.contains("Silence threshold")) // not used in AntiDot mode
        #expect(snapshot.text.contains("Level the volume: Off\n\nDetection")) // AntiDot mode measures no sound
        #expect(!snapshot.text.contains("Lower by at most"))
    }

    @Test("in AntiDot mode, says its longer start for apps without video")
    func saysAntiDotStarts() {
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2))) // as the Mac's region writes it
        #expect(quietReport(.playbackSignals, .playbackSignals).text.contains(
            "Pause playback after: \(half) s\nPause playback after, without video: 3 s\nPause for the microphone: Off"))
    }

    @Test("with open audio streams only, says every app's start: at least 2 s")
    func saysOpenStreamsStarts() {
        #expect(quietReport(.disabled, .openStreams).text.contains("Behavior\nPause playback after: 2 s\nPause for the microphone: Off"))
    }

    @Test("measuring levels without Audio Recording access, says AntiDot mode's starts with it off; measured, the usual ones")
    func saysUnmeasuredStarts() {
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2))) // as the Mac's region writes it
        let unmeasured = quietReport(.unavailable, .audioLevels).text
        #expect(unmeasured.contains("Behavior\nPause playback after: 2 s\nPause playback after, without video: 3 s\n"))
        #expect(unmeasured.contains("Detecting by: Open audio streams (no Audio Recording access)\nAntiDot mode: Off\n"))
        #expect(quietReport(.audioLevel, .audioLevels).text.contains("Behavior\nPause playback after: \(half) s\nPause for the microphone: Off"))
    }

    @Test("a chosen player that isn't installed (Choose… beside it), or can't fade, says so")
    func playerNotInstalled() throws {
        var status = workingStatus()
        status.playerOptions = [PlayerOption(bundleID: "com.example.jukebox", name: "Jukebox", appURL: nil)]
        let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts { $0.playerCanFade = false })
        let rows = try #require(snapshot.sections.first { $0.kind == .player }).rows
        #expect(rows.first == .init(label: "Player", value: "Jukebox · Not installed", mark: .problem, fix: .choosePlayer))
        #expect(rows.last?.value == "No")
    }

    @Test("an app added with Add an App says the ways it's controlled by, in order; one muted instead says so; with its ways unknown, nothing")
    func checkedApp() throws {
        func player(_ ways: [PlayerSetup.Way]?, mutes: Bool = false) throws -> DiagnosticsSnapshot.Section {
            var status = workingStatus()
            status.playerOptions = [PlayerOption(bundleID: "com.example.jukebox", name: "Jukebox", appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"),
                                                 kind: .checkedApp, pausesByMuting: mutes)]
            let snapshot = if let ways {
                DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts(), ways: { $0 == "com.example.jukebox" ? ways : nil })
            } else {
                DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts())
            }
            return try #require(snapshot.sections.first { $0.kind == .player })
        }
        #expect(try player(nil).rows.allSatisfy { $0.label != "Controlled by" })
        let paused = try player([.menu(menuName: "Controls"), .panel(rememberedRow: nil)])
        #expect(paused.rows.contains(.init(label: "State", value: "Paused by AutoHush")))
        #expect(paused.rows.contains(.init(label: "Controlled by", value: "Its playback menu\nThe menu bar’s Now Playing panel")))
        let muted = try player([.mute], mutes: true)
        #expect(muted.summary == "Jukebox · Muted by AutoHush")
        #expect(muted.rows.contains(.init(label: "State", value: "Muted by AutoHush")))
        #expect(muted.rows.contains(.init(label: "Controlled by", value: "Muted instead of paused")))
        // A supported player has no such row.
        let supported = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts(), ways: { _ in [.mute] })
        #expect(try #require(supported.sections.first { $0.kind == .player }).rows.allSatisfy { $0.label != "Controlled by" })
    }

    @Test("fades turned off in Settings read Off; a player that can't fade still reads No")
    func fadesOff() throws {
        func fades(_ change: (inout DiagnosticsFacts) -> Void) throws -> String? {
            let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts(change))
            return try #require(snapshot.sections.first { $0.kind == .player }).rows.first { $0.label == "Fades" }?.value
        }
        #expect(try fades { _ in } == "Yes")
        #expect(try fades { $0.timings.fadesEnabled = false } == "Off")
        #expect(try fades { $0.timings.fadesEnabled = false; $0.playerCanFade = false } == "No")
    }

    @Test("a web app's section says whether its button is learned and its windows on other Spaces reachable")
    func webAppRows() throws {
        func rows(_ change: (inout DiagnosticsFacts) -> Void) throws -> [DiagnosticsSnapshot.Row] {
            let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts(change))
            return try #require(snapshot.sections.first { $0.kind == .player }).rows
        }
        #expect(try rows { _ in }.count == 3)
        #expect(try rows {
            $0.playerLearned = false
            $0.reachesOtherSpaces = true
        }.suffix(2) == [
            .init(label: "Play/Pause button learned", value: "No", mark: .problem, fix: .learnControls),
            .init(label: "Reaches windows on other Spaces", value: "Yes", mark: .ok),
        ])
        #expect(try rows { $0.playerLearned = true }.last == .init(label: "Play/Pause button learned", value: "Yes", mark: .ok))
    }

    @Test("each app's line says how AutoHush judges it, and why", arguments: [
        (ActiveAudioReport.Entry(id: "org.videolan.vlc", state: .starting), "org.videolan.vlc — starting"),
        (.init(id: "com.example.d", state: .starting, isIgnored: true), "com.example.d — starting, ignored"),
        (.init(id: "com.apple.Safari", name: "Safari", state: .silent, isIgnored: true, evidence: .level(0)),
         "Safari (com.apple.Safari) — output open, silent, ignored (silence)"),
        (.init(id: "com.example.a", state: .playing, evidence: .announcing),
         "com.example.a — playing (tells macOS it’s playing)"),
        (.init(id: "com.example.b", state: .silent, evidence: .notAnnouncing),
         "com.example.b — output open, silent (not telling macOS it’s playing)"),
        (.init(id: "com.example.c", state: .playing, isIgnored: true, evidence: .level(0.1)),
         "com.example.c — playing, ignored (-20 dBFS)"),
    ])
    func appLines(entry: ActiveAudioReport.Entry, line: String) {
        #expect(DiagnosticsReport.line(for: entry) == line)
    }
}
