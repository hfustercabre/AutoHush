import Foundation
import Testing
@testable import AutoHushKit

@Suite("PlaybackSignals")
struct PlaybackSignalsTests {
    private struct FixedAssertions: PowerAssertionReading {
        let byProcess: [pid_t: Set<PowerAssertion>]
        func assertionsByProcess() -> [pid_t: Set<PowerAssertion>] { byProcess }
    }

    // Measured names (macOS 27).
    private static let playingAudio = PowerAssertion(.system, "Playing audio")
    private static let videoWakeLock = PowerAssertion(.display, "Video Wake Lock")
    private static let webKitVisible = PowerAssertion(.display, "com.apple.WebCore: HTMLMediaElement playback")
    private static let webKitHidden = PowerAssertion(.system, "com.apple.WebCore: HTMLMediaElement playback")

    /// Judges one app with its sound on, holding `held`, `seconds` into the test.
    private func judge(
        _ signals: inout PlaybackSignals, _ held: Set<PowerAssertion>, app: String = "app", at seconds: TimeInterval = 0
    ) -> PlaybackSignals.Judgement {
        signals.judge(present: [app], holding: [app: held], at: Date(timeIntervalSinceReferenceDate: seconds))
    }

    /// A check with no app's sound on.
    private func soundOff(_ signals: inout PlaybackSignals) {
        _ = signals.judge(present: [], holding: [:], at: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test("an app's assertions are gathered from all its processes, for apps with their sound on only")
    func gathering() {
        let signals = PlaybackSignals(powerAssertions: FixedAssertions(byProcess: [
            10: [Self.playingAudio], 11: [Self.videoWakeLock], 20: [PowerAssertion(.system, "VLC media playback")],
            30: [Self.playingAudio],
        ]), learned: [:])
        let owners: [pid_t: String] = [10: "com.google.Chrome", 11: "com.google.Chrome", 20: "org.videolan.vlc", 30: "com.example.absent"]

        let holding = signals.assertions(among: ["com.google.Chrome", "org.videolan.vlc", "com.apple.Safari"]) { owners[$0] }

        #expect(holding == [
            "com.google.Chrome": [Self.playingAudio, Self.videoWakeLock],
            "org.videolan.vlc": [PowerAssertion(.system, "VLC media playback")],
        ])
    }

    @Test("without an assertion reader nothing is held")
    func noReader() {
        let signals = PlaybackSignals(powerAssertions: nil, learned: [:])
        #expect(signals.assertions(among: ["org.videolan.vlc"]) { _ in "org.videolan.vlc" }.isEmpty)
    }

    @Test("an app keeping the Mac awake plays, and counts as paused once it stops; apps that never did get no verdict")
    func fullAnnouncer() {
        var signals = PlaybackSignals(powerAssertions: nil, learned: [:])
        #expect(judge(&signals, []).verdicts.isEmpty)

        let playing = judge(&signals, [Self.playingAudio, Self.videoWakeLock])
        #expect(playing.verdicts == ["app": true])
        #expect(playing.learned == ["app": AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"])])

        #expect(judge(&signals, []).verdicts == ["app": false]) // paused, its sound still on
        // Muted: the video goes on, but it no longer says it plays.
        #expect(judge(&signals, [Self.videoWakeLock]).verdicts == ["app": false])
        // Remembered, so a new sound that says nothing (a preloaded video) counts as paused.
        soundOff(&signals)
        #expect(judge(&signals, []).verdicts == ["app": false])
    }

    @Test("what an app holds is learned once, and only new names are reported")
    func learning() {
        var signals = PlaybackSignals(powerAssertions: nil, learned: ["app": AnnouncedAssertions(system: ["Playing audio"])])
        #expect(judge(&signals, [Self.playingAudio]).learned.isEmpty)
        #expect(judge(&signals, [Self.playingAudio, Self.videoWakeLock]).learned
            == ["app": AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"])])
        #expect(signals.learned["app"] == AnnouncedAssertions(system: ["Playing audio"], display: ["Video Wake Lock"]))

        // An app naming its assertions differently each time stops being learned from.
        for index in 0..<20 { _ = judge(&signals, [PowerAssertion(.system, "Task \(index)")], app: "busy") }
        #expect(signals.learned["busy"]?.system.count == AnnouncedAssertions.namesLimit)
    }

    @Test("an app using one assertion for video, visible or hidden, counts as playing either way (WebKit)")
    func videoAnnouncer() {
        var signals = PlaybackSignals(powerAssertions: nil, learned: [:])
        // Its first visible video: the display assertion alone isn't trusted yet.
        #expect(judge(&signals, [Self.webKitVisible]).verdicts.isEmpty)
        // Hidden, the same assertion keeps the Mac awake: now it's known.
        #expect(judge(&signals, [Self.webKitHidden]).verdicts == ["app": true])
        #expect(signals.learned["app"]?.announcesVideoOnly == true)
        // Visible again: still playing, where it used to count as paused.
        #expect(judge(&signals, [Self.webKitVisible]).verdicts == ["app": true])
        // Paused, or muted: it withdrew its assertion while its sound was on.
        #expect(judge(&signals, []).verdicts == ["app": false])
    }

    @Test("sound without video from a video-only announcer is judged by its open output (WebKit audio)")
    func videoAnnouncerAudio() {
        let webKit = AnnouncedAssertions(system: [Self.webKitHidden.name], display: [Self.webKitVisible.name])
        var signals = PlaybackSignals(powerAssertions: nil, learned: ["app": webKit])
        // Audio only: it never says anything.
        #expect(judge(&signals, []).verdicts.isEmpty)
        // Its sound goes off and on again: a video, then a pause.
        soundOff(&signals)
        #expect(judge(&signals, [Self.webKitVisible]).verdicts == ["app": true])
        #expect(judge(&signals, []).verdicts == ["app": false])
        // Once its sound has gone off, the next sound starts with no verdict again.
        soundOff(&signals)
        #expect(judge(&signals, []).verdicts.isEmpty)
        // So does a monitor that stopped meanwhile.
        _ = judge(&signals, [Self.webKitVisible])
        signals.forgetAnnouncements()
        #expect(judge(&signals, []).verdicts.isEmpty)
    }

    @Test("a video-only announcer's pause is trusted for 10 s; its sound still on after that counts again")
    func withdrawalTrust() {
        let webKit = AnnouncedAssertions(system: [Self.webKitHidden.name], display: [Self.webKitVisible.name])
        var signals = PlaybackSignals(powerAssertions: nil, learned: ["app": webKit])
        #expect(judge(&signals, [Self.webKitVisible], at: 0).verdicts == ["app": true])
        #expect(judge(&signals, [], at: 0.25).verdicts == ["app": false]) // paused
        #expect(judge(&signals, [], at: 9.75).verdicts == ["app": false])
        // Its sound should have gone off by now: audio started after the pause plays.
        #expect(judge(&signals, [], at: 10.25).verdicts.isEmpty)

        // A full announcer's pause stays trusted (Chrome keeps a muted video's sound on).
        var chrome = PlaybackSignals(powerAssertions: nil, learned: ["app": AnnouncedAssertions(system: ["Playing audio"])])
        #expect(judge(&chrome, [], at: 60).verdicts == ["app": false])
    }

    @Test("apps keeping the display awake show a video; a video-only announcer's hidden video counts too")
    func showingVideo() {
        let webKit = AnnouncedAssertions(system: [Self.webKitHidden.name], display: [Self.webKitVisible.name])
        var signals = PlaybackSignals(powerAssertions: nil, learned: ["safari": webKit])
        let judgement = signals.judge(
            present: ["chrome", "chromeAudio", "safari", "quicktime"],
            holding: ["chrome": [Self.playingAudio, Self.videoWakeLock], "chromeAudio": [Self.playingAudio],
                      "safari": [Self.webKitHidden]],
            at: Date(timeIntervalSinceReferenceDate: 0)
        )
        #expect(judgement.showingVideo == ["chrome", "safari"])
    }
}
