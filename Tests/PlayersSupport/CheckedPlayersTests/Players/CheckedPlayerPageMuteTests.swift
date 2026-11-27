import Foundation
import Testing
@testable import CheckedPlayers
@testable import WebAppPlayers
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

/// An added app whose script tells its state before its page does, its page
/// muted in place of a pause: an ad its site won't pause, its button saying
/// Play while it's heard. Only a read of its page pauses it for real once
/// it can, lifting the mute, or lifts a mute AutoHush no longer holds
/// (T2 of 11-27: its script answering first, its page was never read, so
/// that mute stayed after the pause).
@Suite("CheckedPlayer's page mute under its script", .waitsTimeLimit)
struct CheckedPlayerPageMuteTests {
    /// The app: its script (`script`) first among its signs, then its page,
    /// whose Play/Pause says Pause while `playing`, muted by `muter`.
    private struct Jukebox {
        let script = MockMusicPlayer(state: .paused)
        let playing = Locked(false)
        let muter = FakeMuter()
        let page: StubPage
        let player: CheckedPlayer

        init() {
            page = StubPage(playing: playing)
            let web = page.player(muter: muter)
            let setup = PlayerSetup(bundleID: "com.example.jukebox", name: "Jukebox",
                                    appURL: URL(fileURLWithPath: "/Applications/Jukebox.app"), ways: [.page(.webKit)])
            player = CheckedPlayer(setup: setup, parts: .init(ways: [script, web], signs: [script, web], page: web),
                                   reports: nil, processIdentifier: { 4242 }, audioRecordingAllowed: { true })
        }

        /// The ad is over: the music plays on under the mute, and a press of
        /// its pause takes. `scriptFollows`: its script reads paused after
        /// that press, as the app is paused then.
        func adEnds(scriptFollows: Bool = false) async {
            playing.value = true
            let pressed = Locked(false)
            page.onPress.value = { [playing] in
                playing.value = false
                pressed.value = true
            }
            guard scriptFollows else { return }
            await script.setBeforeStateAnswer { [script] in
                // Once: a play pressed later is read playing.
                if pressed.withLock({ was in defer { was = false }; return was }) { await script.setState(.paused) }
            }
        }

        /// Its window is closed: its page has no buttons and no sound, and
        /// its script reads stopped.
        func closeWindow() async {
            page.windowOpen.value = false
            await script.setState(.stopped)
        }
    }

    @Test("its page's mute held as AutoHush's pause, its script read playing over it (the ad): the ad over just as the resume reads it, before its observer read its page, that read pauses it for real and lifts the mute, and its script is read again: paused, the music is played (U1 of 11-27: the playing read before it skipped the resume, the music left paused)")
    func adEndsAsResumeReads() async {
        let jukebox = Jukebox()
        let arbiter = PlaybackArbiter(player: jukebox.player, configuration: .testing,
                                      debounceScheduler: ManualDebounceScheduler())
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: true)
        await arbiter.waitForPause()
        #expect(await arbiter.heldByMute)
        await jukebox.script.setState(.playing) // the ad, read playing over the mute

        await jukebox.adEnds(scriptFollows: true)
        await arbiter.handleSourceChange(sourceID: "org.example.viewer", isPlaying: false)
        await arbiter.waitUntilIdle()
        #expect(jukebox.page.presses == 1)
        #expect(!jukebox.muter.isMuted)
        #expect(await jukebox.script.playCallCount == 1)
        #expect(await !arbiter.pausedByUs)
    }

    @Test("read by its script while its page is muted, its page is read too: paused for real once the ad is over, the mute lifted, and its script's state still told",
          arguments: [false, true])
    func mutedPageReadUnderScript(polled: Bool) async {
        let jukebox = Jukebox()
        await jukebox.script.setState(.playing) // its script reads playing over its page's mute
        #expect(await jukebox.player.muteIfPlayingAnyway())
        #expect(jukebox.muter.isMuted)
        #expect(await (polled ? jukebox.player.polledState() : jukebox.player.playerState()) == .playing)
        #expect(jukebox.muter.isMuted) // the ad plays on: still muted
        #expect(jukebox.page.presses == 0)

        await jukebox.adEnds()
        #expect(await (polled ? jukebox.player.polledState() : jukebox.player.playerState()) == .playing)
        #expect(jukebox.page.presses == 1)
        #expect(!jukebox.muter.isMuted)
    }

    /// How AutoHush's pause, held by its page's mute, ends with the music
    /// kept paused: the mute is AutoHush's no more (`forgetPause`).
    enum KeptPaused: String, CaseIterable, Sendable {
        case resumeOff, stayPausedAfterCall, outputGone, sleep
    }

    /// What comes to its page under the mute, held as AutoHush's pause.
    enum PageThen: String, CaseIterable, Sendable {
        /// The ad is over once the pause ends: it's paused for real.
        case adEnds
        /// Its window is closed during the pause (its script reads stopped,
        /// AutoHush's pause held: T1 of 11-27): nothing to pause, nothing heard.
        case windowClosed
    }

    @Test("its page's mute held as AutoHush's pause, which ends kept paused (Resume playback off, Stay paused after calls, the output gone, a sleep): its page read under its script lifts that mute once the ad is over, as it's paused for real, or once its window is closed and it's silent (U2 of 11-27: a closed window's mute stayed for good)",
          arguments: KeptPaused.allCases, PageThen.allCases)
    func keptPauseMuteLifted(_ way: KeptPaused, _ then: PageThen) async {
        let jukebox = Jukebox()
        var configuration = AppConfiguration.testing
        let call = "us.zoom.xos", app = way == .stayPausedAfterCall ? call : "org.example.viewer"
        switch way {
        case .resumeOff: configuration.resumesPlayback = false
        case .stayPausedAfterCall: configuration.staysPausedAfterCalls = true
        case .outputGone: configuration.pausesOnOutputDisconnect = true
        case .sleep: break
        }
        let arbiter = PlaybackArbiter(player: jukebox.player, configuration: configuration,
                                      debounceScheduler: ManualDebounceScheduler())
        if way == .stayPausedAfterCall { await arbiter.handleCallChange(sourceID: call, inCall: true) }
        await arbiter.handleSourceChange(sourceID: app, isPlaying: true)
        await arbiter.waitForPause()
        #expect(await arbiter.heldByMute) // its script says paused, its page is heard: muted
        #expect(jukebox.muter.isMuted)
        if then == .windowClosed {
            await jukebox.closeWindow()
            await arbiter.handlePlayerStateChange(.stopped)
            #expect(await arbiter.pausedByUs) // held: no sign of the user (T1)
            #expect(jukebox.muter.isMuted)
        }

        switch way {
        case .resumeOff:
            await arbiter.handleSourceChange(sourceID: app, isPlaying: false)
        case .stayPausedAfterCall:
            await arbiter.handleCallChange(sourceID: call, inCall: false)
            await arbiter.handleSourceChange(sourceID: app, isPlaying: false)
        case .outputGone:
            await arbiter.handleOutputDisconnected()
        case .sleep:
            await arbiter.setAsleep(true)
            await arbiter.handleSourceChange(sourceID: app, isPlaying: false)
            await arbiter.setAsleep(false)
        }
        await arbiter.waitUntilIdle()
        #expect(await !arbiter.pausedByUs)
        #expect(await jukebox.script.playCallCount == 0)

        switch then {
        case .adEnds:
            await jukebox.adEnds()
            #expect(await jukebox.player.polledState() == .paused) // as its observer reads it
            #expect(jukebox.page.presses == 1)
        case .windowClosed:
            #expect(await jukebox.player.polledState() == .stopped) // as its observer reads it
            #expect(jukebox.page.presses == 0)
        }
        #expect(!jukebox.muter.isMuted)
    }
}
