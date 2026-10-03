import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushPlayers
import SpotifySupport
import AutoHushTestSupport

@Suite("DiagnosticsReport")
struct DiagnosticsReportTests {
    @Test("lists the apps with sound, the detection, auto-pause and ignored apps")
    func fullReport() {
        var status = AppStatus()
        status.detection = .audioLevel
        status.autoPause = .snoozed(until: "15:30")
        status.ignoredApps = [AudioSource(id: "org.videolan.vlc", name: "VLC")]

        let text = DiagnosticsReport.text(
            activeAudio: ["Google Chrome (com.google.Chrome) — playing (-20 dBFS)"],
            status: status,
            detectionMethod: .audioLevels
        )
        #expect(text == """
            Google Chrome (com.google.Chrome) — playing (-20 dBFS)

            Detection: audio levels

            Auto-pause: off until 15:30

            Ignored apps: VLC
            """)
    }

    @Test("says when nothing plays, nothing is ignored, and AntiDot mode is on")
    func quietReport() {
        var status = AppStatus()
        status.detection = .playbackSignals
        let text = DiagnosticsReport.text(activeAudio: [], status: status, detectionMethod: .playbackSignals)
        #expect(text.hasPrefix("No foreign audio output currently detected."))
        #expect(text.contains("Detection: what apps tell macOS — AntiDot mode"))
        #expect(text.contains("Auto-pause: on"))
        #expect(text.hasSuffix("Ignored apps: none"))
    }
}
