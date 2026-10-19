import Foundation
import Testing
import AutoHushKit
import AutoHushTestSupport
@testable import AutoHushApp

@Suite("HeldPauses", .timeLimit(.minutes(1)))
@MainActor
struct HeldPausesTests {
    @Test("a held pause's monitoring runs on while its player is paused by it, and stops once it plays again")
    func stopsOncePlaying() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        #expect(held.choose("com.spotify.client", leaving: "org.videolan.vlc", current: monitoring, token: token,
                            holdsPause: true)) // kept: left running
        #expect(held.bundleIDs == ["org.videolan.vlc"])

        #expect(held.takes(.playback(.pausedByMonitor), from: token)) // still holding it
        #expect(held.takes(.detection(.audioLevel), from: token))
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.videolan.vlc"]) // not ending: it would stop only later

        #expect(held.takes(.playback(.musicPlaying), from: token)) // the other apps stopped: it plays again
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)
        #expect(!held.takes(.playback(.musicPlaying), from: token)) // no longer kept
    }

    @Test("a held pause's monitoring stops only once its player has faded back in, which stopping would cut short")
    func stopsAfterFadeIn() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")
        monitoring.beginResume() // the other apps stopped: it plays, fading in
        #expect(held.takes(.playback(.musicPlaying), from: token))
        await TestWait.until { monitoring.isWaitingForResume } // it stops only once that wait is over
        #expect(monitoring.stops == 0 && !held.isEmpty)
        #expect(held.bundleIDs.isEmpty) // its pause is over: not handed over at a quit
        #expect(held.takes(.playback(.musicPlaying), from: token)) // still its own

        monitoring.endResume()
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)
    }

    @Test("a held pause that is ending pauses nothing more, whatever Auto-Pause is set to meanwhile")
    func endingPausesNothing() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")
        held.setAutoPauseEnabled(true)
        #expect(monitoring.autoPause == true)
        monitoring.beginResume() // the other apps stopped: it plays, fading in
        _ = held.takes(.playback(.musicPlaying), from: token)
        // An app starting now would have it pause a player that isn't chosen.
        #expect(monitoring.autoPause == false)
        held.setAutoPauseEnabled(true) // the user turns Auto-Pause on meanwhile
        #expect(monitoring.autoPause == false)

        monitoring.endResume()
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)
    }

    @Test("a player chosen again while it fades back in is taken back at once, and its monitoring stopped once")
    func takenBackWhileFadingIn() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")
        monitoring.beginResume()
        _ = held.takes(.playback(.musicPlaying), from: token)
        #expect(held.takeBack("org.videolan.vlc"))
        #expect(monitoring.stops == 1 && held.isEmpty)

        monitoring.endResume()
        await TestWait.until { monitoring.resumeWaitsOver == 1 }
        #expect(monitoring.stops == 1)
    }

    @Test("not holding a pause, the monitoring left isn't kept")
    func notKeptWithoutPause() {
        let held = HeldPauses()
        #expect(!held.choose("com.spotify.client", leaving: "org.videolan.vlc", current: FakeMonitoring(), token: UUID(),
                             holdsPause: false))
        #expect(held.isEmpty)
    }

    @Test("monitoring started for a handed-over pause ignores the state it first finds, until it has taken the pause over")
    func awaitingTakeOver() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc", awaitingTakeOver: true)
        #expect(held.takes(.playback(.musicIdle), from: token)) // its first look: paused, not by it yet
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.videolan.vlc"])
        #expect(held.takes(.playback(.pausedByMonitor), from: token)) // taken over
        _ = held.takes(.playback(.musicPlaying), from: token) // then played again
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)

        // Nothing to take over (played or quit meanwhile): dropped.
        let other = FakeMonitoring()
        let otherToken = UUID()
        held.keep(other, token: otherToken, bundleID: "org.videolan.vlc", awaitingTakeOver: true)
        held.drop(otherToken)
        #expect(other.stops == 1 && held.isEmpty)
    }

    @Test("the user taking the player over stops it too; an unknown state doesn't")
    func stopsWhenTakenOver() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, bundleID: "org.videolan.vlc")
        _ = held.takes(.playback(.unknown), from: token)
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.videolan.vlc"])
        _ = held.takes(.playback(.musicIdle), from: token) // the user stopped or quit it
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1)
    }

    @Test("what AntiDot learns in a held pause's monitoring goes to the app; the current monitoring's updates aren't taken")
    func learnedAssertionsAndCurrent() {
        let held = HeldPauses()
        let token = UUID()
        held.keep(FakeMonitoring(), token: token, bundleID: "org.videolan.vlc")
        #expect(!held.takes(.learnedAssertions("com.example.video", AnnouncedAssertions()), from: token))
        #expect(!held.takes(.playback(.musicPlaying), from: UUID()))
    }

    @Test("a player chosen again is taken back by its next monitoring only, once; another player's start ends the wait")
    func takeBack() {
        let held = HeldPauses()
        let vlc = FakeMonitoring()
        _ = held.choose("com.spotify.client", leaving: "org.videolan.vlc", current: vlc, token: UUID(), holdsPause: true)
        #expect(!held.choose("org.videolan.vlc", leaving: "com.spotify.client", current: nil, token: UUID(), holdsPause: false))
        #expect(vlc.stops == 1 && held.isEmpty)
        #expect(held.takesBack("org.videolan.vlc"))
        #expect(!held.takesBack("org.videolan.vlc")) // once

        // Taken back, but another player starts first: not that one's pause.
        let again = FakeMonitoring()
        _ = held.choose("com.spotify.client", leaving: "org.videolan.vlc", current: again, token: UUID(), holdsPause: true)
        _ = held.choose("org.videolan.vlc", leaving: "com.spotify.client", current: nil, token: UUID(), holdsPause: false)
        #expect(!held.takesBack("com.apple.Music"))
        #expect(!held.takesBack("org.videolan.vlc"))
    }

    @Test("Auto-Pause, the ignored apps and the detection method reach held monitoring; keeping a player again stops its earlier monitoring")
    func settingsAndReplacing() {
        let held = HeldPauses()
        let first = FakeMonitoring()
        held.keep(first, token: UUID(), bundleID: "org.videolan.vlc")
        held.setAutoPauseEnabled(false)
        held.setIgnoredSources(["com.example.video"])
        held.setDetectionMethod(.playbackSignals)
        #expect(first.autoPause == false && first.ignored == ["com.example.video"])
        #expect(first.detectionMethods == [.playbackSignals])

        let second = FakeMonitoring()
        held.keep(second, token: UUID(), bundleID: "org.videolan.vlc")
        #expect(first.stops == 1 && held.bundleIDs == ["org.videolan.vlc"])
    }

    @Test("sleep forgets them all; quitting stops each with its volume back")
    func sleepAndQuit() async {
        let held = HeldPauses()
        let vlc = FakeMonitoring()
        let spotify = FakeMonitoring()
        held.keep(vlc, token: UUID(), bundleID: "org.videolan.vlc")
        held.keep(spotify, token: UUID(), bundleID: "com.spotify.client")
        held.stopAll()
        #expect(vlc.stops == 1 && spotify.stops == 1 && held.isEmpty)

        let fading = FakeMonitoring()
        held.keep(fading, token: UUID(), bundleID: "org.videolan.vlc")
        await held.stopAndRestoreAll()
        #expect(fading.restoredStops == 1 && held.isEmpty)
    }
}
