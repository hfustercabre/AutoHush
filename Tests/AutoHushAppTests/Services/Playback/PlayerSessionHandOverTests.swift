import CoreAudio
import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
@testable import CheckedPlayers
import AutoHushTestSupport
import PlayersTestSupport

/// A pause held by a mute, taken back (the player chosen again, checked
/// again and used, or its permission back): the new monitoring holds it
/// before the one before lets go, so the music is never heard over the
/// video meanwhile (app-services-2, diff-app-1). On the engine's real
/// pipelines, which the stand-in monitorings couldn't show this with (R3
/// and S1 of 2026-11-19: the old stop lifted the page's mute the new
/// monitoring had taken over).
@MainActor
@Suite("PlayerSession: a pause held by a mute, taken back", .waitsTimeLimit)
struct PlayerSessionHandOverTests {
    /// What mutes the player in place of its pause.
    enum Muting: String, CustomTestStringConvertible, Sendable {
        /// A page's own mute: its site refuses the pause.
        case page
        /// A page's own mute during an ad, its button reading Play, heard
        /// through that mute by the monitor (P1 of 11-27: its pause, with no
        /// `pausedAt`, was taken for the user's then, and it stayed muted).
        case ad
        /// The same, its page saying it's stopped meanwhile.
        case adStopped
        /// AutoHush's own tap: the player refuses its pause.
        case tap
        /// AutoHush's own tap, made as the player was heard while it said
        /// it's paused (`mutesHeardWhileQuiet`): it still says so when it's
        /// taken back (N1 of 11-27).
        case tapWhileQuiet
        /// An app added as Mute It Instead (`MutedApp`), its own tap.
        case mutedApp

        var testDescription: String { rawValue }
    }

    /// How the pause is taken back.
    enum TakeBack: String, CustomTestStringConvertible, Sendable {
        /// Another player chosen, then this one again.
        case chosenAgain
        /// The same app chosen as a new player object (Check Again, then Use).
        case checkedAgain
        /// Its permission found missing, and back by the start that follows.
        case permissionBack

        var testDescription: String { rawValue }
    }

    @Test("a pause held by a mute, taken back, is never heard over the video: unmuted once, when it stops",
          arguments: [
              (Muting.page, TakeBack.chosenAgain), (.ad, .chosenAgain), (.tap, .chosenAgain), (.tapWhileQuiet, .chosenAgain),
              (.mutedApp, .chosenAgain),
              (.page, .checkedAgain), (.ad, .checkedAgain), (.adStopped, .checkedAgain), (.tap, .checkedAgain),
              (.tapWhileQuiet, .checkedAgain), (.mutedApp, .checkedAgain),
              (.page, .permissionBack), (.tap, .permissionBack), (.tapWhileQuiet, .permissionBack),
          ])
    func neverHeardOverVideo(_ muting: Muting, _ takeBack: TakeBack) async {
        let rig = Rig()
        let player = await rig.player(muting)
        let session = await rig.mutedForVideo(player)
        switch takeBack {
        case .chosenAgain:
            session.choose(rig.other)
            await TestWait.until { session.state.health == .ready && rig.pipelines.count == 2 }
            session.choose(player)
        case .checkedAgain:
            session.choose(await rig.player(muting))
        case .permissionBack:
            await rig.denyOnce(player)
            session.checkAccess()
        }
        let pipelines = takeBack == .chosenAgain ? 3 : 2
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) {
            rig.pipelines.count == pipelines && session.state.health == .ready && session.state.playback == .pausedByMonitor
        }
        await rig.settle()
        #expect(rig.sound.isMuted)

        rig.videoStops()
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) { !rig.sound.isMuted }
        await rig.settle()
        #expect(rig.sound.heardOverVideo == [])
        #expect(rig.sound.heardAfterVideo == 1)
        await session.quit()?.value
    }

    @Test("a page muted for an ad, heard through its mute during the video: still AutoHush's pause, unmuted once, when it stops (P1 of 11-27)",
          arguments: [Muting.ad, .adStopped])
    func adHeardThroughItsMute(_ muting: Muting) async {
        let rig = Rig()
        let session = await rig.mutedForVideo(await rig.player(muting))
        await TestWait.until { await rig.pipelines.last?.monitor.playerHearing() == .heard }
        await rig.settle() // the monitor told the arbiter it hears the page
        #expect(session.state.playback == .pausedByMonitor)
        #expect(rig.sound.isMuted)

        rig.videoStops()
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) { !rig.sound.isMuted }
        await rig.settle()
        #expect(rig.sound.heardOverVideo == [])
        #expect(rig.sound.heardAfterVideo == 1)
        await session.quit()?.value
    }

    @Test("its permission still missing at the start that would take it back: the mute is lifted, as before")
    func permissionStillMissing() async {
        let rig = Rig()
        let page = PageMutingPlayer(bundleID: TestPlayers.first, name: "First", tap: rig.sound.tap())
        let session = await rig.mutedForVideo(page)
        page.deny(1_000)
        session.checkAccess()
        await TestWait.until { session.state.health == .needsPermission(.accessibility(player: "First")) }
        await rig.settle()
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) { !rig.sound.isMuted }
        #expect(rig.pipelines.count == 1)
        await session.quit()?.value
    }

    /// The player held paused by AutoHush's tap, another chosen, then the
    /// player again, its start held at its access check: `during` happens
    /// then, and the start goes on.
    private func takenBackDuringCheck(_ rig: Rig, during: (PlayerSession) async -> Void) async -> PlayerSession {
        let player = MockMusicPlayer(bundleID: TestPlayers.first, name: "First", failPauseWith: MockMusicPlayer.refused)
        let session = await rig.mutedForVideo(player)
        session.choose(rig.other)
        await TestWait.until { session.state.health == .ready && rig.pipelines.count == 2 }
        let checking = ManualSleep()
        await player.setBeforeVerify { await checking.sleep(.zero) }
        session.choose(player)
        await TestWait.until { checking.sleeping == 1 }
        await during(session)
        checking.timeIsUp()
        await session.waitUntilIdle()
        await rig.settle()
        return session
    }

    @Test("the Mac sleeping while the start that takes it back checks the player: the mute is lifted, as any pause then")
    func sleepDuringTakeBack() async {
        let rig = Rig()
        let session = await takenBackDuringCheck(rig) { $0.setAsleep(true) }
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) { !rig.sound.isMuted }
        #expect(rig.pipelines.count == 3)
        await session.quit()?.value
    }

    @Test("AutoHush quitting while the start that takes it back checks the player: the mute is lifted, and nothing starts after")
    func quitDuringTakeBack() async {
        let rig = Rig()
        _ = await takenBackDuringCheck(rig) { session in
            await session.quit()?.value
            #expect(!rig.sound.isMuted)
        }
        #expect(!rig.sound.isMuted)
        #expect(rig.pipelines.count == 2)
    }

    @Test("AntiDot mode turned on while the start that takes it back checks the player: no tap is left, its mute included")
    func antiDotDuringTakeBack() async {
        let rig = Rig()
        let session = await takenBackDuringCheck(rig) { session in
            session.settings.detection = .playbackSignals
        }
        await TestWait.until(otherwise: { "\(rig.sound.changes)" }) { !rig.sound.isMuted }
        #expect(rig.pipelines.count == 3)
        await session.quit()?.value
    }
}

extension PlayerSessionHandOverTests {
    /// The player session as the app runs it, its monitorings the engine's
    /// pipelines on stand-ins for macOS, each with readers of its own: the
    /// player's app, whose sound is `sound` and is heard by the monitor
    /// (through a mute, as a tap hears it), and a video that starts and
    /// stops. Another player, paused, can be chosen in between.
    @MainActor
    final class Rig {
        nonisolated static let appPID: pid_t = 999_998
        /// Process IDs no process can have, so the real owner lookup finds none.
        nonisolated static let playerProcess = AudioProcessInfo(objectID: 1, bundleID: TestPlayers.first, pid: appPID)
        nonisolated static let video = AudioProcessInfo(objectID: 2, bundleID: "org.example.viewer", pid: 999_999)
        static let settings = MonitoringSettings(autoPause: true, ignored: [],
                                                 timings: TimingSettings(startConfirmation: 0, fadesEnabled: false),
                                                 detection: .audioLevels)

        let sound = AppSound()
        let other = MockMusicPlayer(bundleID: TestPlayers.second, name: "Second", state: .paused)
        /// The monitorings made, in order.
        private(set) var pipelines: [MonitoringPipeline] = []
        private var readersMade: [(processes: MockAudioProcessSnapshotProvider, meter: MockLevelMeter)] = []
        private var processes = [Rig.playerProcess]
        private var peaks: [AudioObjectID: Float] = [Rig.playerProcess.objectID: 0.3]

        /// A new player object for the player's app, muted in place of its pause by `muting`.
        func player(_ muting: Muting) async -> any MusicPlayer {
            switch muting {
            case .page:
                return PageMutingPlayer(bundleID: TestPlayers.first, name: "First", tap: sound.tap())
            case .ad, .adStopped:
                return PageMutingPlayer(bundleID: TestPlayers.first, name: "First", tap: sound.tap(),
                                        ad: muting == .ad ? .paused : .stopped)
            case .tap:
                return MockMusicPlayer(bundleID: TestPlayers.first, name: "First", failPauseWith: MockMusicPlayer.refused)
            case .tapWhileQuiet:
                // It plays until the video does, then says it's paused, heard
                // all the same; read late (a polled state), so that pause
                // isn't taken for the video's doing.
                let player = MockMusicPlayer(bundleID: TestPlayers.first, name: "First", stateReportDelay: 5)
                await player.setBeforeStateAnswer { [sound, player] in
                    if sound.videoPlays { await player.setState(.paused) }
                }
                return player
            case .mutedApp:
                return MutedApp(setup: PlayerSetup(bundleID: TestPlayers.first, name: "First",
                                                   appURL: URL(fileURLWithPath: "/Applications/First.app"), ways: [.mute]),
                                processIdentifier: { Rig.appPID }, muter: sound.tap(), soundOn: { _ in true },
                                assertionsHeld: { _ in [] }, audioRecordingAllowed: { true })
            }
        }

        /// The next access check of `player` fails, its permission missing; the one after passes.
        func denyOnce(_ player: any MusicPlayer) async {
            if let page = player as? PageMutingPlayer { page.deny(1) }
            if let mock = player as? MockMusicPlayer {
                let checks = Locked(0)
                await mock.setFailVerify(MusicPlayerError.accessibilityPermissionDenied)
                await mock.setBeforeVerify { [mock] in
                    checks.increment()
                    if checks.value == 2 { await mock.setFailVerify(nil) }
                }
            }
        }

        func session(_ chosen: any MusicPlayer) -> PlayerSession {
            let pipelines = PlayerSession.pipelines(hostedApp: { _ in nil }, readers: { [unowned self] in self.readers() })
            return PlayerSession(
                player: chosen,
                players: MusicPlayerCatalog(players: [chosen, other]),
                preferences: Preferences(store: InMemoryPreferenceStore()),
                settings: Self.settings,
                makeMonitoring: { [unowned self] player, setup, onUpdate in
                    let monitoring = pipelines(player, setup, onUpdate)
                    if let pipeline = monitoring as? MonitoringPipeline { self.pipelines.append(pipeline) }
                    return monitoring
                },
                locateApp: { URL(fileURLWithPath: "/Applications/\($0).app") },
                retries: PlayerSession.Retries(permissionInterval: 0.05, delays: 0.02...0.08)
            )
        }

        /// A session with `player` chosen, the video playing and the player
        /// muted in place of its pause, as AutoHush's pause.
        func mutedForVideo(_ player: any MusicPlayer) async -> PlayerSession {
            let session = session(player)
            session.launch()
            await TestWait.until { session.state.health == .ready }
            await TestWait.until { self.readersMade.last?.processes.isObserving == true }
            videoPlays()
            await TestWait.until(otherwise: { "\(session.state), \(self.sound.changes)" }) {
                session.state.playback == .pausedByMonitor && self.sound.isMuted
            }
            await session.waitUntilIdle() // the access check the video's start called for is over
            return session
        }

        private func readers() -> MonitoringPipeline.Readers {
            let made = (processes: MockAudioProcessSnapshotProvider(), meter: MockLevelMeter())
            made.processes.processes = processes
            made.meter.peaks = peaks
            readersMade.append(made)
            return .standIns(processes: made.processes, levelMeter: made.meter, playerMute: { [sound] bundleID, allowed in
                ProcessPlayerMute(bundleID: bundleID, muter: sound.tap(), tapsAllowed: allowed,
                                  running: { $0 == TestPlayers.first ? Rig.appPID : nil }, audioRecordingAllowed: { true })
            })
        }

        func videoPlays() {
            sound.setVideoPlays(true)
            processes = [Self.playerProcess, Self.video]
            peaks[Self.video.objectID] = 0.5
            announce()
        }

        func videoStops() {
            sound.setVideoPlays(false)
            processes = [Self.playerProcess]
            peaks[Self.video.objectID] = nil
            announce()
        }

        /// The audio server announces the change to every monitor.
        private func announce() {
            for made in readersMade {
                made.processes.processes = processes
                made.meter.peaks = peaks
                made.processes.triggerChange()
            }
        }

        /// What the monitorings were told has reached them: those stopped
        /// have shut down, the last one has settled.
        func settle() async {
            for stopped in pipelines.dropLast() { await stopped.stopAndRestoreVolume() }
            await pipelines.last?.settled()
        }
    }
}
