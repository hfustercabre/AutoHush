import Darwin
import Testing
@testable import AutoHushKit

@Suite("PlaybackSignals")
struct PlaybackSignalsTests {
    private struct FixedAssertions: PowerAssertionReading {
        let pids: Set<pid_t>
        func pidsKeepingSystemAwake() -> Set<pid_t> { pids }
    }

    @Test("an app announces playback when one of its processes holds an assertion")
    func announcingApps() {
        let signals = PlaybackSignals(powerAssertions: FixedAssertions(pids: [10, 20, 30]), announcingSourceIDs: [])
        let owners: [pid_t: String] = [10: "com.google.Chrome", 20: "org.videolan.vlc", 30: "com.example.absent"]

        let announcing = signals.appsAnnouncingPlayback(among: ["com.google.Chrome", "org.videolan.vlc", "com.apple.Safari"]) {
            owners[$0]
        }

        #expect(announcing == ["com.google.Chrome", "org.videolan.vlc"]) // only apps with sound on
    }

    @Test("without an assertion reader nothing announces")
    func noReader() {
        let signals = PlaybackSignals(powerAssertions: nil, announcingSourceIDs: [])
        #expect(signals.appsAnnouncingPlayback(among: ["org.videolan.vlc"]) { _ in "org.videolan.vlc" }.isEmpty)
    }

    @Test("playing while announcing, paused once it stops, no verdict for apps that never announced")
    func verdicts() {
        var signals = PlaybackSignals(powerAssertions: nil, announcingSourceIDs: [])
        #expect(signals.isPlaying("org.videolan.vlc", isAnnouncing: false) == nil)

        let first = signals.remember("org.videolan.vlc")
        let second = signals.remember("org.videolan.vlc")
        #expect(first && !second) // only the first time is new
        #expect(signals.isPlaying("org.videolan.vlc", isAnnouncing: true) == true)
        #expect(signals.isPlaying("org.videolan.vlc", isAnnouncing: false) == false)
    }
}
