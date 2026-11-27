import Foundation
import Testing
@testable import AutoHushKit
import AutoHushTestSupport
@testable import AutoHushApp

@Suite("HeldPauses", .waitsTimeLimit)
@MainActor
struct HeldPausesTests {
    private let viewer = MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer")
    private let streamer = MockMusicPlayer(bundleID: "com.example.streamer", name: "Streamer")
    private let radio = MockMusicPlayer(bundleID: "com.example.radio", name: "Radio")
    private let library = MockMusicPlayer(bundleID: "com.example.library", name: "Library")

    @Test("a held pause's monitoring runs on while its player is paused by it, and stops once it plays again")
    func stopsOncePlaying() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        #expect(held.choose(streamer, leaving: viewer, current: monitoring, token: token,
                            holdsPause: true)) // kept: left running
        #expect(held.bundleIDs == ["org.example.viewer"])

        #expect(held.takes(.playback(.pausedByMonitor), from: token)) // still holding it
        #expect(held.takes(.detection(.audioLevel), from: token))
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.example.viewer"]) // not ending: it would stop only later

        #expect(held.takes(.playback(.musicPlaying), from: token)) // the other apps stopped: it plays again
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)
        #expect(!held.takes(.playback(.musicPlaying), from: token)) // no longer kept
    }

    @Test("a held pause's monitoring shows no kept mute: its player isn't chosen, so a mute it would keep with no app playing is lifted instead (D2)")
    func heldShowsNoKeptMute() {
        let held = HeldPauses()
        let leaving = FakeMonitoring(), handedOver = FakeMonitoring()
        _ = held.choose(streamer, leaving: viewer, current: leaving, token: UUID(), holdsPause: true)
        held.keep(handedOver, token: UUID(), player: radio, awaitingTakeOver: true)
        #expect(leaving.keptMutesShown == [false])
        #expect(handedOver.keptMutesShown == [false])
    }

    @Test("a held pause's monitoring stops only once its player has faded back in, which stopping would cut short")
    func stopsAfterFadeIn() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, player: viewer)
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
        held.keep(monitoring, token: token, player: viewer)
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

    @Test("a player chosen again while it fades back in is taken back at once, and its monitoring stopped once: nothing is parked")
    func takenBackWhileFadingIn() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, player: viewer)
        monitoring.beginResume()
        _ = held.takes(.playback(.musicPlaying), from: token)
        #expect(!held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false))
        #expect(monitoring.stops == 1 && held.isEmpty)
        #expect(held.takesBack("org.example.viewer")?.heldBy == nil) // only a real pause to take back, if any

        monitoring.endResume()
        await TestWait.until { monitoring.resumeWaitsOver == 1 }
        #expect(monitoring.stops == 1)
    }

    @Test("not holding a pause, the monitoring left isn't kept")
    func notKeptWithoutPause() {
        let held = HeldPauses()
        #expect(!held.choose(streamer, leaving: viewer, current: FakeMonitoring(), token: UUID(), holdsPause: false))
        #expect(held.isEmpty)
    }

    @Test("monitoring started for a handed-over pause ignores the state it first finds, until it has taken the pause over")
    func awaitingTakeOver() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, player: viewer, awaitingTakeOver: true)
        #expect(held.takes(.playback(.musicIdle), from: token)) // its first look: paused, not by it yet
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.example.viewer"])
        #expect(held.takes(.playback(.pausedByMonitor), from: token)) // taken over
        _ = held.takes(.playback(.musicPlaying), from: token) // then played again
        await TestWait.until { monitoring.stops == 1 }
        #expect(monitoring.stops == 1 && held.isEmpty)

        // Nothing to take over (played or quit meanwhile): dropped.
        let other = FakeMonitoring()
        let otherToken = UUID()
        held.keep(other, token: otherToken, player: viewer, awaitingTakeOver: true)
        held.drop(otherToken)
        #expect(other.stops == 1 && held.isEmpty)
    }

    @Test("the user taking the player over stops it too; an unknown state doesn't")
    func stopsWhenTakenOver() async {
        let held = HeldPauses()
        let monitoring = FakeMonitoring()
        let token = UUID()
        held.keep(monitoring, token: token, player: viewer)
        _ = held.takes(.playback(.unknown), from: token)
        #expect(monitoring.stops == 0 && held.bundleIDs == ["org.example.viewer"])
        _ = held.takes(.playback(.musicIdle), from: token) // the user stopped or quit it
        await TestWait.until { monitoring.stops == 1 }
    }

    @Test("what AntiDot learns in a held pause's monitoring goes to the app; the current monitoring's updates aren't taken")
    func learnedAssertionsAndCurrent() {
        let held = HeldPauses()
        let token = UUID()
        held.keep(FakeMonitoring(), token: token, player: viewer)
        #expect(!held.takes(.learnedAssertions("com.example.video", AnnouncedAssertions()), from: token))
        #expect(!held.takes(.playback(.musicPlaying), from: UUID()))
    }

    @Test("a player chosen again is taken back by its next monitoring only, once, the one that held it parked till then; another player's start ends the wait, and what was parked stops as before")
    func takeBack() throws {
        let held = HeldPauses()
        let holding = FakeMonitoring()
        _ = held.choose(streamer, leaving: viewer, current: holding, token: UUID(), holdsPause: true)
        #expect(!held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false))
        // Parked, its resumes held: its pause stays until the new one has it.
        #expect(holding.stops == 0 && holding.resumesHeld == [true])
        #expect(held.bundleIDs.isEmpty && !held.isEmpty)
        let takeBack = try #require(held.takesBack("org.example.viewer"))
        #expect(held.takesBack("org.example.viewer") == nil) // once
        #expect(holding.stops == 0) // until the start is over
        held.handOver(takeBack, tookOver: true, to: viewer)
        #expect(holding.handOverStops == 1 && holding.stops == 0 && held.isEmpty)
        held.handOver(takeBack, tookOver: true, to: viewer) // once
        #expect(holding.handOverStops == 1)

        // Taken back twice before its start (the first one's left still
        // shown as holding a pause): what's parked stays for that start.
        let twice = FakeMonitoring()
        _ = held.choose(streamer, leaving: viewer, current: twice, token: UUID(), holdsPause: true)
        _ = held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        _ = held.choose(viewer, leaving: viewer, current: nil, token: UUID(), holdsPause: true)
        #expect(twice.stops == 0)
        held.handOver(try #require(held.takesBack("org.example.viewer")), tookOver: true, to: viewer)
        #expect(twice.handOverStops == 1 && twice.stops == 0)

        // Taken back, but another player starts first: not that one's pause.
        let again = FakeMonitoring()
        _ = held.choose(streamer, leaving: viewer, current: again, token: UUID(), holdsPause: true)
        _ = held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        #expect(held.takesBack("com.example.library") == nil)
        #expect(again.stops == 1 && again.handOverStops == 0 && held.isEmpty)
        #expect(held.takesBack("org.example.viewer") == nil)
    }

    @Test("the start that took the pause back didn't take it over: what held it stops as before, its mutes lifted")
    func takeBackNotTakenOver() throws {
        let held = HeldPauses()
        let holding = FakeMonitoring()
        _ = held.choose(streamer, leaving: viewer, current: holding, token: UUID(), holdsPause: true)
        _ = held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        held.handOver(try #require(held.takesBack("org.example.viewer")), tookOver: false, to: viewer)
        #expect(holding.stops == 1 && holding.handOverStops == 0)
    }

    @Test("a held one muted in place of its pause by its tap is taken back as such, as it last said")
    func takeBackMutedInstead() throws {
        let held = HeldPauses()
        let token = UUID()
        _ = held.choose(streamer, leaving: viewer, current: FakeMonitoring(), token: token, holdsPause: true, mutedInstead: true)
        _ = held.takes(.mutedInstead(false), from: token) // paused for real since
        _ = held.takes(.mutedInstead(true), from: token) // muted again: an app started
        _ = held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        let takeBack = try #require(held.takesBack("org.example.viewer"))
        #expect(takeBack.mutedInstead)
        #expect(takeBack.heldBy.map { PlayerSession.isSame($0, viewer) } == true)

        _ = held.choose(streamer, leaving: viewer, current: FakeMonitoring(), token: token, holdsPause: true)
        _ = held.choose(viewer, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        #expect(held.takesBack("org.example.viewer")?.mutedInstead == false)
    }

    @Test("the same app chosen again with a new player (checked again) while its pause is held: the monitoring that holds it is parked until the new one has taken it over, then stops as before, the old player let go of")
    func sameAppChosenAgain() async throws {
        let held = HeldPauses()
        let current = FakeMonitoring()
        let old = MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer", releasesOnQuit: true)
        let checkedAgain = MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer", releasesOnQuit: true)
        #expect(held.choose(checkedAgain, leaving: old, current: current, token: UUID(), holdsPause: true)) // left running
        #expect(held.bundleIDs.isEmpty && current.stops == 0)
        #expect(held.releasesOnceParkedStops(old) && !held.releasesOnceParkedStops(checkedAgain))
        let takeBack = try #require(held.takesBack("org.example.viewer"))
        #expect(await old.releases == 0)
        // Another player object: its own mutes are its own to lift.
        held.handOver(takeBack, tookOver: true, to: checkedAgain)
        #expect(current.stops == 1 && current.handOverStops == 0)
        await TestWait.until { await old.releases == 1 }
        #expect(!held.releasesOnceParkedStops(old))

        // Not holding a pause: nothing to take over.
        #expect(!held.choose(checkedAgain, leaving: checkedAgain, current: current, token: UUID(), holdsPause: false))
        #expect(held.takesBack("org.example.viewer") == nil)
    }

    @Test("a parked monitoring no start takes the pause from stops as before: its access check failed, a newer take-back, sleep; quitting stops it with its volume back and lets go of its player")
    func parkedEnds() async throws {
        let held = HeldPauses()
        func parked(_ leaving: any MusicPlayer = MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer")) -> FakeMonitoring {
            let monitoring = FakeMonitoring()
            _ = held.choose(MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer", releasesOnQuit: true), leaving: leaving,
                            current: monitoring, token: UUID(), holdsPause: true)
            return monitoring
        }
        let failed = parked()
        held.endParked()
        #expect(failed.stops == 1 && held.isEmpty)
        #expect(held.takesBack("org.example.viewer") != nil) // a real pause is still taken back

        let replaced = parked()
        _ = held.choose(streamer, leaving: library, current: FakeMonitoring(), token: UUID(), holdsPause: true)
        _ = held.choose(library, leaving: streamer, current: nil, token: UUID(), holdsPause: false)
        #expect(replaced.stops == 1)
        _ = held.takesBack("com.example.library")
        held.stopAll()

        let asleep = parked()
        held.stopAll()
        #expect(asleep.stops == 1 && held.isEmpty)
        let starting = parked()
        let takeBack = try #require(held.takesBack("org.example.viewer"))
        held.stopAll() // while its start runs: that start finds nothing to hand over
        held.handOver(takeBack, tookOver: true, to: viewer)
        #expect(starting.stops == 1 && starting.handOverStops == 0)

        let old = MockMusicPlayer(bundleID: "org.example.viewer", name: "Viewer", releasesOnQuit: true)
        let quitting = parked(old)
        await held.stopAndRestoreAll()
        #expect(quitting.restoredStops == 1 && held.isEmpty)
        #expect(await old.releases == 1)
    }

    @Test("Auto-Pause, the ignored apps and the detection method reach held monitoring, the detection method parked ones too; keeping a player again stops its earlier monitoring")
    func settingsAndReplacing() {
        let held = HeldPauses()
        let first = FakeMonitoring()
        held.keep(first, token: UUID(), player: viewer)
        held.setAutoPauseEnabled(false)
        held.setIgnoredSources(["com.example.video"])
        held.setDetectionMethod(.playbackSignals)
        #expect(first.autoPause == false && first.ignored == ["com.example.video"])
        #expect(first.detectionMethods == [.playbackSignals])

        let second = FakeMonitoring()
        held.keep(second, token: UUID(), player: viewer)
        #expect(first.stops == 1 && held.bundleIDs == ["org.example.viewer"])

        let parked = FakeMonitoring()
        _ = held.choose(streamer, leaving: streamer, current: parked, token: UUID(), holdsPause: true)
        held.setAutoPauseEnabled(true)
        held.setDetectionMethod(.audioLevels) // AntiDot mode off: no tap is left behind either way
        #expect(parked.autoPause == nil && parked.detectionMethods == [.audioLevels])
    }

    @Test("later timings and switches reach held monitoring, each for its own player: Resume playback turned off meanwhile keeps its pause (K1-7)")
    func configurationFollows() {
        let held = HeldPauses()
        let viewerMonitoring = FakeMonitoring()
        let libraryMonitoring = FakeMonitoring()
        held.keep(viewerMonitoring, token: UUID(), player: viewer)
        held.keep(libraryMonitoring, token: UUID(), player: library)
        var configuration = AppConfiguration(timings: TimingSettings(resumesPlayback: false))
        configuration.musicPlayerBundleID = "com.example.chosen"
        held.setConfiguration(configuration)

        #expect(viewerMonitoring.configurations.map(\.resumesPlayback) == [false])
        #expect(libraryMonitoring.configurations.map(\.resumesPlayback) == [false])
        // Its own player's audio still never counts as another app playing.
        #expect(viewerMonitoring.configurations.map(\.musicPlayerBundleID) == ["org.example.viewer"])
        #expect(libraryMonitoring.configurations.map(\.musicPlayerBundleID) == ["com.example.library"])
    }

    @Test("sleep forgets them all; quitting stops each with its volume back")
    func sleepAndQuit() async {
        let held = HeldPauses()
        let viewerMonitoring = FakeMonitoring()
        let streamerMonitoring = FakeMonitoring()
        held.keep(viewerMonitoring, token: UUID(), player: viewer)
        held.keep(streamerMonitoring, token: UUID(), player: streamer)
        held.stopAll()
        #expect(viewerMonitoring.stops == 1 && streamerMonitoring.stops == 1 && held.isEmpty)

        let fading = FakeMonitoring()
        held.keep(fading, token: UUID(), player: viewer)
        await held.stopAndRestoreAll()
        #expect(fading.restoredStops == 1 && held.isEmpty)
    }
}
