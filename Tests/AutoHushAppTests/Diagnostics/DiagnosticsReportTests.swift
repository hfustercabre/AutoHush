import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("DiagnosticsReport")
struct DiagnosticsReportTests {
    @Test("lists the apps with sound, the detection, the music player, auto-pause and ignored apps")
    func fullReport() {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.detection = .audioLevel
        status.autoPause = .snoozed("until 15:30")
        status.ignoredApps = [AudioSource(id: "org.videolan.vlc", name: "VLC")]

        let text = DiagnosticsReport.text(
            activeAudio: [.init(id: "com.google.Chrome", name: "Google Chrome", state: .playing, evidence: .level(0.1))],
            status: status,
            detectionMethod: .audioLevels
        )
        #expect(text == """
            Google Chrome (com.google.Chrome) — playing (-20 dBFS)

            Detection: audio levels

            Music player: Jukebox

            Auto-pause: off until 15:30

            Ignored apps: VLC
            """)
    }

    @Test("the Diagnostics tab gets each app with its icon, how it's judged and why, then the settings, and the text to copy")
    func snapshot() {
        var status = AppStatus()
        status.choosePlayer(named: "Jukebox")
        status.detection = .audioLevel
        let activeAudio: [ActiveAudioReport.Entry] = [
            .init(id: "com.google.Chrome", name: "Google Chrome", state: .playing, evidence: .level(0.1)),
            .init(id: "org.videolan.vlc", state: .silent, isIgnored: true),
        ]
        let snapshot = DiagnosticsReport.snapshot(
            activeAudio: activeAudio, status: status, detectionMethod: .audioLevels,
            bundlePath: { $0 == "com.google.Chrome" ? "/Applications/Google Chrome.app" : nil }
        )
        #expect(snapshot.apps == [
            .init(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app",
                  judgement: "Playing", evidence: "-20 dBFS"),
            .init(id: "org.videolan.vlc", name: "org.videolan.vlc", bundlePath: nil,
                  judgement: "Output open, silent, ignored", evidence: nil),
        ])
        #expect(snapshot.settings == ["Detection: audio levels", "Music player: Jukebox", "Auto-pause: on", "Ignored apps: none"])
        #expect(snapshot.text == DiagnosticsReport.text(activeAudio: activeAudio, status: status, detectionMethod: .audioLevels))
    }

    @Test("each app's line says how AutoHush judges it, and why", arguments: [
        (ActiveAudioReport.Entry(id: "org.videolan.vlc", state: .starting), "org.videolan.vlc — starting"),
        (.init(id: "com.apple.Safari", name: "Safari", state: .silent, isIgnored: true, evidence: .level(0)),
         "Safari (com.apple.Safari) — output open, silent, ignored (silence)"),
        (.init(id: "com.example.a", state: .playing, evidence: .announcing),
         "com.example.a — playing (tells macOS it is playing)"),
        (.init(id: "com.example.b", state: .silent, evidence: .notAnnouncing),
         "com.example.b — output open, silent (not telling macOS it is playing)"),
        (.init(id: "com.example.c", state: .playing, isIgnored: true, evidence: .level(0.1)),
         "com.example.c — playing, ignored (-20 dBFS)"),
    ])
    func appLines(entry: ActiveAudioReport.Entry, line: String) {
        #expect(DiagnosticsReport.line(for: entry) == line)
    }

    @Test("says when nothing plays, no player is chosen, nothing is ignored, and AntiDot mode is on")
    func quietReport() {
        var status = AppStatus()
        status.detection = .playbackSignals
        let text = DiagnosticsReport.text(activeAudio: [], status: status, detectionMethod: .playbackSignals)
        #expect(text.hasPrefix("No foreign audio output currently detected."))
        #expect(text.contains("Detection: what apps tell macOS — AntiDot mode"))
        #expect(text.contains("Music player: none chosen"))
        #expect(text.contains("Auto-pause: on"))
        #expect(text.hasSuffix("Ignored apps: none"))
    }
}
