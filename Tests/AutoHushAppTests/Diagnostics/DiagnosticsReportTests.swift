import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

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

            Music Player
            Player: Jukebox 2.1
            State: Paused by AutoHush
            Fades: Yes

            Detection
            Detecting by: Audio levels
            AntiDot mode: Off
            Pause music after: \(half) s
            Resume music after: 2 s
            Silence threshold: -60 dB

            Permissions
            Audio recording: Allowed
            Automation for Jukebox: Allowed
            Notifications: Allowed

            AutoHush
            Version: 0.6.1 (19)
            Auto-Pause: On
            Ignored apps: VLC
            Launch at login: On
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
        #expect(snapshot.sections.map(\.kind) == [.player, .detection, .permissions, .autoHush, .mac])
        #expect(snapshot.sections.map(\.summary) == [
            "Jukebox · Paused by AutoHush", "Audio levels", "All allowed", "Version 0.6.1 (19)", "macOS 27.0.1 (26A434)",
        ])
    }

    @Test("the card on top: working, needs attention, auto-pause off, starting")
    func overview() {
        var attention = workingStatus()
        attention.setHealth(.needsPermission(.automation(player: "Jukebox")))
        var snoozed = workingStatus()
        snoozed.autoPause = .snoozed("until 15:30")
        let kinds = [workingStatus(), attention, snoozed, AppStatus()].map {
            DiagnosticsReport.snapshot(activeAudio: [], status: $0, facts: facts()).overview
        }
        #expect(kinds.map(\.kind) == [.working, .attention, .off, .starting])
        #expect(kinds[1].detail == "Allow Automation access to control Jukebox")
        #expect(kinds[2].title == "Auto-Pause is off until 15:30")
    }

    @Test("permissions: allowed, refused, not needed in AntiDot mode, and not checked yet, each with its mark")
    func permissions() throws {
        func rows(_ change: (inout DiagnosticsFacts) -> Void) throws -> [DiagnosticsSnapshot.Row] {
            let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts(change))
            return try #require(snapshot.sections.first { $0.kind == .permissions }).rows
        }
        #expect(try rows { _ in } == [
            .init(label: "Audio recording", value: "Allowed", mark: .ok),
            .init(label: "Automation for Jukebox", value: "Allowed", mark: .ok),
            .init(label: "Notifications", value: "Allowed", mark: .ok),
        ])
        #expect(try rows {
            $0.audioRecording = .denied
            $0.playerPermission = .accessibility(player: "Jukebox")
            $0.playerPermissionGranted = false
            $0.notificationsOff = true
        } == [
            .init(label: "Audio recording", value: "Not allowed", mark: .problem),
            .init(label: "Accessibility for Jukebox", value: "Not allowed", mark: .problem),
            .init(label: "Notifications", value: "Off", mark: .neutral),
        ])
        #expect(try rows {
            $0.audioRecording = .notDetermined
            $0.detectionMethod = .playbackSignals
            $0.playerPermissionGranted = nil
        }.map(\.value) == ["Not needed in AntiDot mode", "Not checked yet", "Allowed"])

        let refused = DiagnosticsReport.snapshot(activeAudio: [], status: workingStatus(), facts: facts { $0.audioRecording = .denied })
        #expect(refused.sections.first { $0.kind == .permissions }?.summary == "Something's missing")
    }

    @Test("says when nothing plays, no player is chosen, nothing is ignored, and AntiDot mode is on, with its longer start without video")
    func quietReport() {
        var status = AppStatus()
        status.setHealth(.ready)
        status.detection = .playbackSignals
        let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts {
            $0.detectionMethod = .playbackSignals
            $0.playerPermission = nil
            $0.checksForUpdates = false
            $0.lastUpdateCheck = nil
        })
        #expect(snapshot.appsSummary == "None")
        #expect(snapshot.text.contains("Apps with Sound\nNo foreign audio output currently detected."))
        #expect(snapshot.text.contains("Player: None chosen"))
        #expect(snapshot.text.contains("Detecting by: What apps tell macOS\nAntiDot mode: On"))
        #expect(!snapshot.text.contains("Silence threshold")) // not used in AntiDot mode
        let half = 0.5.formatted(.number.precision(.fractionLength(0...2))) // as the Mac's region writes it
        #expect(snapshot.text.contains("Pause music after: \(half) s\nPause music after, without video: 3 s\nResume music after: 2 s"))
        #expect(snapshot.text.contains("Ignored apps: None"))
        #expect(snapshot.text.contains("Updates: Automatic checks off\nLast checked: Never"))
    }

    @Test("a chosen player that isn't installed, or can't fade, says so")
    func playerNotInstalled() throws {
        var status = workingStatus()
        status.playerOptions = [PlayerOption(bundleID: "com.example.jukebox", name: "Jukebox", appURL: nil)]
        let snapshot = DiagnosticsReport.snapshot(activeAudio: [], status: status, facts: facts { $0.playerCanFade = false })
        let rows = try #require(snapshot.sections.first { $0.kind == .player }).rows
        #expect(rows.first == .init(label: "Player", value: "Jukebox · Not installed", mark: .problem))
        #expect(rows.last?.value == "No")
    }

    @Test("each app's line says how AutoHush judges it, and why", arguments: [
        (ActiveAudioReport.Entry(id: "org.videolan.vlc", state: .starting), "org.videolan.vlc — starting"),
        (.init(id: "com.apple.Safari", name: "Safari", state: .silent, isIgnored: true, evidence: .level(0)),
         "Safari (com.apple.Safari) — output open, silent, ignored (silence)"),
        (.init(id: "com.example.a", state: .playing, evidence: .announcing),
         "com.example.a — playing (tells macOS it's playing)"),
        (.init(id: "com.example.b", state: .silent, evidence: .notAnnouncing),
         "com.example.b — output open, silent (not telling macOS it's playing)"),
        (.init(id: "com.example.c", state: .playing, isIgnored: true, evidence: .level(0.1)),
         "com.example.c — playing, ignored (-20 dBFS)"),
    ])
    func appLines(entry: ActiveAudioReport.Entry, line: String) {
        #expect(DiagnosticsReport.line(for: entry) == line)
    }
}
