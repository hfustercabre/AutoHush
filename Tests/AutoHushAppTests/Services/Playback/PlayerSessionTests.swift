import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("PlayerSession", .waitsTimeLimit)
struct PlayerSessionTests {
    private typealias Players = TestPlayers

    private static let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    private static let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
    private static let settings = MonitoringSettings(autoPause: true, ignored: [], timings: TimingSettings(),
                                                     detection: .audioLevels)

    /// In-memory preferences, two stand-in players that may be controlled
    /// (a test refuses it with `setFailVerify`), both installed, and
    /// monitorings that stand in for the engine.
    @MainActor
    private final class Bench {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let first = MockMusicPlayer(bundleID: Players.first, name: "First")
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second")
        lazy var players = MusicPlayerCatalog(players: [first, second], formerDefault: Players.first)
        var installed: Set<String> = [Players.first, Players.second]
        let monitorings = FakeMonitorings()
        /// The waits between startup checks, each over once the test steps it.
        let startupWaits = ManualSleep()
        /// The states a session told, in order, once `record` is called.
        var changes: [PlayerSession.State] = []

        func record(_ session: PlayerSession) {
            session.didChange = { [weak self] in self?.changes.append($0) }
        }

        func makeSession(_ chosen: any MusicPlayer?) -> PlayerSession {
            PlayerSession(
                player: chosen,
                players: players,
                preferences: preferences,
                settings: PlayerSessionTests.settings,
                makeMonitoring: monitorings.make,
                // Weak: a session may still be retrying a start once its test is over.
                locateApp: { [weak self] id in
                    self?.installed.contains(id) == true ? URL(fileURLWithPath: "/Applications/\(id).app") : nil
                },
                retries: PlayerSession.Retries(permissionInterval: 0.05, delays: 0.02...0.08, startupWait: startupWaits.sleep)
            )
        }

        /// A session monitoring the first player, ready.
        func started() async -> PlayerSession {
            let session = makeSession(first)
            session.launch()
            await TestWait.until { session.state.health == .ready }
            return session
        }

        /// A session with the second player chosen, found not running as it
        /// launched, done starting.
        func secondNotRunning() async -> PlayerSession {
            await second.setFailVerify(MusicPlayerError.playerNotRunning)
            let session = makeSession(second)
            session.launch()
            await TestWait.until { session.state.health != .starting }
            await session.waitUntilIdle()
            return session
        }

        /// The first player chosen, monitored and paused by AutoHush, then
        /// the second chosen: the first's pause is held.
        func holdingFirst() async -> PlayerSession {
            let session = await started()
            monitorings.made[0].send(.playback(.pausedByMonitor))
            session.choose(second)
            await TestWait.until { session.state.health == .ready && !self.monitorings.of(Players.second).isEmpty }
            return session
        }
    }

    // MARK: - Starting

    @MainActor
    @Test("a start that succeeds monitors the chosen player with the settings, and says it's ready")
    func startSucceeds() async {
        let bench = Bench()
        let session = bench.makeSession(bench.first)
        #expect(session.state.health == .starting)

        session.launch()
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.made.count == 1)
        let monitoring = bench.monitorings.made[0]
        #expect(monitoring.bundleID == Players.first)
        #expect(monitoring.setup?.settings == Self.settings)
        #expect(monitoring.starts.map(\.takingOverPause) == [false])
        #expect(await bench.first.verifyCallCount == 1)
        #expect(session.state.controlError == nil)
    }

    @MainActor
    @Test("only the chosen player's audio is the music; other players count like any app")
    func onlyChosenPlayerIsProtected() async {
        let bench = Bench()
        _ = await bench.started()
        let configuration = bench.monitorings.made[0].setup?.configuration
        #expect(configuration?.musicPlayerBundleID == Players.first)
        #expect(configuration?.isMediaSource(Players.first) == false)
        #expect(configuration?.isMediaSource(Players.second) == true)
    }

    @MainActor
    @Test("what the monitoring reports is the session's state; the apps seen and the signals learned are kept")
    func monitoringUpdates() async {
        let bench = Bench()
        let session = await bench.started()
        let monitoring = bench.monitorings.made[0]
        bench.record(session)

        monitoring.send(.playback(.pausedByMonitor))
        monitoring.send(.detection(.audioLevel))
        monitoring.send(.activeSources([Self.vlc]))
        monitoring.send(.learnedAssertions(Self.vlc.id, AnnouncedAssertions(system: ["Playing audio"])))
        #expect(session.state.playback == .pausedByMonitor)
        #expect(session.state.detection == .audioLevel)
        #expect(session.state.activeSources == [Self.vlc])
        #expect(bench.preferences.seenApps.map(\.id) == [Self.vlc.id])
        #expect(bench.preferences.playbackAssertions[Self.vlc.id] == AnnouncedAssertions(system: ["Playing audio"]))
        #expect(bench.changes.count == 3)
        #expect(session.isHoldingPause)
    }

    @MainActor
    @Test("while the player needs a permission, starting is tried again every few seconds")
    func retriesWhilePermissionMissing() async {
        let bench = Bench()
        await bench.first.setFailVerify(MusicPlayerError.automationPermissionDenied)
        let session = bench.makeSession(bench.first)
        session.launch()
        await TestWait.until { await bench.first.verifyCallCount >= 3 }
        #expect(session.state.health == .needsPermission(.automation(player: "First")))
        #expect(bench.monitorings.made.isEmpty)
        // Logged as an error once; the repeats are the same problem.
        #expect(session.loggedStartupProblem == "First: \(MusicPlayerError.automationPermissionDenied.localizedDescription)")

        // Allowed: the next try starts monitoring.
        await bench.first.setFailVerify(nil)
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.made.count == 1)
    }

    @MainActor
    @Test("a busy or hung player is asked again by itself, less and less often, until Retry starts the waits over")
    func retriesWhilePlayerNotResponding() async {
        let bench = Bench()
        await bench.second.setFailVerify(MusicPlayerError.playerNotResponding)
        let session = bench.makeSession(bench.second)
        session.launch()
        await TestWait.until { session.failedStarts >= 3 } // each wait longer than the one before
        #expect(await bench.second.verifyCallCount >= 3)
        #expect(session.state.health == .retrying("Second isn’t responding"))
        session.retry()
        #expect(session.failedStarts == 0)
    }

    @MainActor
    @Test("a player that isn't running isn't asked again until it opens, then it's started")
    func noRetryWhilePlayerNotRunning() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        #expect(await bench.second.verifyCallCount == 1)
        #expect(session.state.health == .playerClosed("Second isn’t running"))
        #expect(session.retryTimer == nil) // started on as it opens, not before

        await bench.second.setFailVerify(nil)
        session.playerLaunched(Players.second)
        #expect(session.state.health == .starting)
        await TestWait.until { session.state.health == .ready }
        #expect(await bench.second.verifyCallCount == 2)
        #expect(bench.monitorings.made.count == 2) // the first lists the apps while it's closed
    }

    @MainActor
    @Test("while the player isn't running, another app opening does nothing")
    func otherAppOpeningDoesNothing() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        session.playerLaunched(Players.first)
        session.playerLaunched("org.videolan.vlc")
        await session.waitUntilIdle()
        #expect(session.state.health == .playerClosed("Second isn’t running"))
        #expect(await bench.second.verifyCallCount == 1) // not asked again
    }

    @MainActor
    @Test("a player just opened and not ready for the first check is asked again a moment later")
    func askedAgainWhenJustOpened() async {
        let bench = Bench()
        let session = await bench.started()
        await bench.first.setFailVerify(MusicPlayerError.playerNotRunning)
        session.playerLaunched(Players.first)
        await TestWait.until { bench.startupWaits.sleeping == 1 }
        await bench.first.setFailVerify(nil)
        bench.startupWaits.step()
        await TestWait.until { session.state.health == .ready }
        #expect(await bench.first.verifyCallCount == 3) // at launch, as it opened, and a moment later
        #expect(bench.monitorings.made.count == 2) // at launch, and once it answered
    }

    @MainActor
    @Test("Retry clicked while a player just opened waits to be asked again takes over: the start waiting gives up")
    func retryTakesOverFromWaitingStart() async {
        let bench = Bench()
        let session = await bench.started()
        await bench.first.setFailVerify(MusicPlayerError.playerNotRunning)
        session.playerLaunched(Players.first)
        await TestWait.until { bench.startupWaits.sleeping == 1 }
        await bench.first.setFailVerify(nil)
        session.retry()
        await TestWait.until { session.state.health == .ready }
        bench.startupWaits.step()
        await session.waitUntilIdle()
        #expect(await bench.first.verifyCallCount == 3) // at launch, as it opened, and Retry's
        #expect(bench.monitorings.made.count == 2) // at launch, and Retry's
        #expect(bench.monitorings.made.last?.isStopped == false)
    }

    @MainActor
    @Test("while the player isn't open, the apps are listed at the idle rate, as nothing can be paused; opened, it's watched at the active rate again")
    func listingAtIdleRate() async {
        let bench = Bench()
        await bench.second.setFailVerify(MusicPlayerError.playerNotRunning)
        let session = bench.makeSession(bench.second)
        session.launch()
        await TestWait.until { bench.monitorings.made.count == 1 }
        let listing = bench.monitorings.made[0].setup?.configuration
        #expect(listing?.activeSampleInterval == listing?.idleSampleInterval)

        await bench.second.setFailVerify(nil)
        session.playerLaunched(Players.second)
        await TestWait.until { session.state.health == .ready }
        let watching = bench.monitorings.made.last?.setup?.configuration
        #expect(watching?.activeSampleInterval == AppConfiguration(timings: TimingSettings()).activeSampleInterval)
        #expect(watching?.activeSampleInterval != watching?.idleSampleInterval)
    }

    @MainActor
    @Test("while the player isn't running and Auto-Pause is on, a monitoring lists the apps playing, the line still saying it isn't running")
    func listsAppsWhilePlayerIsClosed() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        #expect(session.state.health == .playerClosed("Second isn’t running"))
        let listening = bench.monitorings.of(Players.second)
        #expect(listening.count == 1 && listening[0].starts.map(\.takingOverPause) == [false])
        listening[0].send(.activeSources([Self.vlc]))
        #expect(session.state.activeSources == [Self.vlc]) // listed
        #expect(session.state.health == .playerClosed("Second isn’t running")) // still says so
    }

    @MainActor
    @Test("while the player isn't running, Auto-Pause off stops listing the apps until it's on again")
    func autoPauseOffStopsListing() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        let listening = bench.monitorings.of(Players.second)
        listening[0].send(.activeSources([Self.vlc]))

        var off = session.settings
        off.autoPause = false
        session.settings = off // Auto-Pause off (or off for a while)
        #expect(listening[0].isStopped)
        #expect(session.state.activeSources.isEmpty)
        var on = session.settings
        on.autoPause = true
        session.settings = on
        await session.waitUntilIdle()
        #expect(bench.monitorings.of(Players.second).count == 2)
        #expect(bench.monitorings.of(Players.second)[1].isStopped == false)
    }

    @MainActor
    @Test("the player opening replaces the monitoring listing the apps with one started as usual, which Auto-Pause off keeps running")
    func openingStartsMonitoringAsUsual() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        await bench.second.setFailVerify(nil)
        session.playerLaunched(Players.second) // it opens: started as usual
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.of(Players.second)[0].isStopped)
        #expect(bench.monitorings.of(Players.second).count == 2)
        var off = session.settings
        off.autoPause = false
        session.settings = off
        #expect(bench.monitorings.of(Players.second)[1].isStopped == false) // running: Auto-Pause off keeps it
    }

    @MainActor
    @Test("with Auto-Pause off as the player is found not running, nothing runs until it's turned on")
    func notListeningWithAutoPauseOff() async {
        let bench = Bench()
        await bench.second.setFailVerify(MusicPlayerError.playerNotRunning)
        let session = bench.makeSession(bench.second)
        var off = session.settings
        off.autoPause = false
        session.settings = off
        session.launch()
        await TestWait.until { session.state.health != .starting }
        await session.waitUntilIdle()
        #expect(bench.monitorings.made.isEmpty)
        var on = off
        on.autoPause = true
        session.settings = on
        await session.waitUntilIdle()
        #expect(bench.monitorings.made.count == 1)
    }

    @Test("the waits between automatic starts double up to a ceiling")
    func retryDelays() {
        #expect((1...6).map { PlayerSession.retryDelay(afterFailedStarts: $0, delays: 5...60) } == [5, 10, 20, 40, 60, 60])
    }

    @Test("startup retries only while the player is not ready yet")
    func transientStartupErrors() {
        #expect(PlayerSession.isTransientStartupError(MusicPlayerError.playerNotResponding))
        #expect(PlayerSession.isTransientStartupError(MusicPlayerError.playerNotRunning))
        #expect(!PlayerSession.isTransientStartupError(MusicPlayerError.automationPermissionDenied))
        #expect(!PlayerSession.isTransientStartupError(MusicPlayerError.playerCommandFailed(.appleEventError(-50))))
        #expect(!PlayerSession.isTransientStartupError(StubError.failed))
    }

    @MainActor
    @Test("a start that fails with the player's error says AutoHush can't control it, and keeps why for the menu")
    func failedStartKeepsItsCause() async {
        let bench = Bench()
        await bench.first.setFailVerify(MusicPlayerError.playerCommandFailed(.menuItemNotFound))
        let session = bench.makeSession(bench.first)
        session.launch()
        await TestWait.until { session.state.health != .starting }
        #expect(session.state.health == .retrying(AppHealthState.cantControl("First")))
        #expect(session.state.controlError?.text == "AutoHush can’t find Play/Pause in First’s menus.")

        // Monitoring once it can: the cause goes.
        await bench.first.setFailVerify(nil)
        await TestWait.until { session.state.health == .ready }
        #expect(session.state.controlError == nil)

        // A pause that fails once it runs says why too, and the cause goes once it's over.
        let monitoring = bench.monitorings.made[0]
        monitoring.send(.pauseFailure(.playerCommandFailed(.pressIgnored)))
        #expect(session.state.controlError?.text == "First didn’t respond to its Play/Pause.")
        monitoring.send(.pauseFailure(nil))
        #expect(session.state.controlError == nil)
    }

    @MainActor
    @Test("a web app macOS doesn't know of yet is started from where it is, as it's listed")
    func webAppStartsFromItsOwnPlace() async {
        let bench = Bench()
        let webApp = MockLearningPlayer(bundleID: "com.apple.Safari.WebApp.new", name: "New Site", status: .learned,
                                        installedURL: URL(fileURLWithPath: "/Users/someone/Applications/New Site.app"))
        // Not in `installed`: Launch Services hasn't caught up with it.
        let session = bench.makeSession(webApp)
        session.launch()
        await TestWait.until { session.state.health != .starting }
        // Past the install check, it stopped at the permission one.
        #expect(session.state.health == .needsPermission(.accessibility(player: "New Site")))
    }

    @MainActor
    @Test("a player that isn't installed says so; gone while it runs, nothing runs; back, it starts again")
    func installedOrNot() async {
        let bench = Bench()
        bench.installed = []
        let session = bench.makeSession(bench.first)
        session.launch()
        await TestWait.until { session.state.health != .starting }
        #expect(session.state.health == .degraded("First isn’t installed"))
        #expect(await bench.first.verifyCallCount == 0)

        bench.installed = [Players.first]
        session.setPlayerInstalled(true)
        await TestWait.until { session.state.health == .ready }
        let monitoring = bench.monitorings.made[0]
        monitoring.send(.playback(.musicPlaying))

        session.setPlayerInstalled(false)
        #expect(session.state.health == .degraded("First isn’t installed"))
        #expect(session.state.playback == .unknown)
        #expect(monitoring.isStopped)
        session.setPlayerInstalled(false) // told again: nothing changes
        #expect(monitoring.stops == 1)
    }

    @MainActor
    @Test("choosing no player stops everything, and the state says none is chosen")
    func chooseNone() async {
        let bench = Bench()
        let session = await bench.started()
        session.choose(nil)
        #expect(session.player == nil)
        #expect(session.state.health == nil)
        #expect(session.state.playback == .unknown)
        #expect(bench.monitorings.made[0].isStopped)
    }

    @MainActor
    @Test("a monitoring torn down leaves no playback state behind, nor do its last updates, so no stale pause is handed over")
    func playbackStateEndsWithMonitoring() async {
        let bench = Bench()
        let session = await bench.started()
        bench.monitorings.made[0].send(.playback(.pausedByMonitor))
        bench.monitorings.made[0].send(.detection(.audioLevel))

        // The permission went: the start over stops at its check.
        await bench.first.setFailVerify(MusicPlayerError.automationPermissionDenied)
        session.checkAccess()
        await TestWait.until { session.state.health == .needsPermission(.automation(player: "First")) }
        // What the stopped monitoring still had on its way arrives late: only what AntiDot learned counts.
        bench.monitorings.made[0].send(.playback(.pausedByMonitor))
        bench.monitorings.made[0].send(.pauseFailure(.playerCommandFailed(.pressIgnored)))
        bench.monitorings.made[0].send(.learnedAssertions(Self.vlc.id, AnnouncedAssertions(system: ["Playing audio"])))
        #expect(session.state.controlError == nil)
        #expect(bench.preferences.playbackAssertions[Self.vlc.id] == AnnouncedAssertions(system: ["Playing audio"]))
        #expect(session.state.playback == .unknown)
        #expect(session.state.detection == .pending)
        #expect(!session.isHoldingPause)
        #expect(session.quit() == nil)
        #expect(bench.preferences.pauseHandover == nil)
    }

    @MainActor
    @Test("a player muted in place of the pause is muted in the state as the monitoring says; once monitoring stops it's muted no more, nor by the stopped one's late updates")
    func mutedInsteadEndsWithMonitoring() async {
        let bench = Bench()
        let session = await bench.started()
        let monitoring = bench.monitorings.made[0]
        monitoring.send(.playback(.pausedByMonitor))
        monitoring.send(.mutedInstead(true))
        #expect(session.state.mutedInstead)
        monitoring.send(.mutedInstead(false)) // paused again
        #expect(!session.state.mutedInstead)

        monitoring.send(.mutedInstead(true))
        session.choose(nil) // nothing runs any more
        #expect(!session.state.mutedInstead)
        monitoring.send(.mutedInstead(true)) // on its way as it stopped
        #expect(!session.state.mutedInstead)
    }

    // MARK: - Checking access while it runs

    @MainActor
    @Test("access is checked again when another app starts playing, and a permission taken away starts over")
    func lostPermissionNoticedWhenOthersPlay() async {
        let bench = Bench()
        let session = await bench.started()
        let monitoring = bench.monitorings.made[0]

        monitoring.send(.activeSources([Self.vlc]))
        await TestWait.until { await bench.first.verifyCallCount == 2 }
        // Still playing: not checked again.
        monitoring.send(.activeSources([Self.safari, Self.vlc]))
        await session.waitUntilIdle()
        #expect(await bench.first.verifyCallCount == 2)
        #expect(session.state.health == .ready)

        monitoring.send(.activeSources([]))
        await bench.first.setFailVerify(MusicPlayerError.automationPermissionDenied)
        monitoring.send(.activeSources([Self.vlc]))
        await TestWait.until { session.state.health == .needsPermission(.automation(player: "First")) }
        #expect(monitoring.isStopped)
        #expect(session.state.activeSources.isEmpty)
    }

    @MainActor
    @Test("checking control access starts over only for a missing permission, and only while monitoring runs")
    func controlAccessCheck() async {
        let bench = Bench()
        let session = bench.makeSession(bench.first)
        session.checkAccess() // not monitoring yet
        await session.waitUntilIdle()
        #expect(await bench.first.verifyCallCount == 0)

        session.launch()
        await TestWait.until { session.state.health == .ready }
        for error: MusicPlayerError? in [nil, .playerNotRunning, .playerNotResponding] {
            await bench.first.setFailVerify(error)
            let calls = await bench.first.verifyCallCount
            session.checkAccess()
            await TestWait.until { await bench.first.verifyCallCount > calls }
            await session.waitUntilIdle()
        }
        #expect(session.state.health == .ready)
        #expect(!bench.monitorings.made[0].isStopped)

        await bench.first.setFailVerify(MusicPlayerError.accessibilityPermissionDenied)
        session.checkAccess()
        await TestWait.until { session.state.health == .needsPermission(.accessibility(player: "First")) }
        #expect(bench.monitorings.made[0].isStopped)
    }

    // MARK: - Settings and sleep

    @MainActor
    @Test("settings reach the chosen player's monitoring and the held pauses, which follow all but the timings")
    func settingsReachMonitorings() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]

        session.settings.autoPause = false
        #expect(current.autoPause == false && held.autoPause == false)
        session.settings.ignored = [Self.vlc.id]
        #expect(current.ignored == [Self.vlc.id] && held.ignored == [Self.vlc.id])
        session.settings.timings = TimingSettings(stopGrace: 4)
        #expect(current.configurations.map(\.musicPlayerBundleID) == [Players.second])
        #expect(current.configurations.first?.sourceStopGrace == 4)
        session.settings.detection = .playbackSignals
        #expect(current.detectionMethods == [.playbackSignals])
        // AntiDot mode leaves no audio taps behind in a held pause.
        #expect(held.detectionMethods == [.playbackSignals])
        #expect(held.configurations.isEmpty)

        let unchanged = session.settings
        session.settings = unchanged // nothing changed: nothing sent
        #expect(current.configurations.count == 1 && current.detectionMethods.count == 1)
    }

    @MainActor
    @Test("the Mac asleep: the monitoring knows, held pauses end, and one started meanwhile knows too")
    func sleep() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]

        session.setAsleep(true)
        session.setAsleep(true)
        #expect(current.asleep == [true])
        #expect(held.isStopped)

        session.retry() // the player relaunched in a dark wake, say
        await TestWait.until { bench.monitorings.of(Players.second).count == 2 }
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.of(Players.second)[1].starts.map(\.asleep) == [true])
        session.setAsleep(false)
        #expect(bench.monitorings.of(Players.second)[1].asleep == [false])
    }

    @MainActor
    @Test("resumes held: the monitoring and the held pauses know, one started meanwhile starts held, and all hear the release")
    func holdResumes() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        let current = bench.monitorings.of(Players.second)[0]
        #expect(current.setup?.resumesHeld == false)

        session.holdResumes(true)
        session.holdResumes(true)
        #expect(current.resumesHeld == [true] && held.resumesHeld == [true])

        session.retry() // the player reopened during Add an App's check, say
        await TestWait.until { bench.monitorings.of(Players.second).count == 2 }
        await TestWait.until { session.state.health == .ready }
        let restarted = bench.monitorings.of(Players.second)[1]
        #expect(restarted.setup?.resumesHeld == true)
        session.holdResumes(false)
        #expect(restarted.resumesHeld == [false] && held.resumesHeld == [true, false])
    }

    // MARK: - Held pauses and the hand-over

    @MainActor
    @Test("choosing another player while AutoHush holds the music paused keeps that pause; chosen again, it's taken back")
    func heldPause() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        #expect(!held.isStopped) // runs on to end its pause
        #expect(session.isHoldingPause)

        session.choose(bench.first)
        #expect(held.isStopped)
        await TestWait.until { bench.monitorings.of(Players.first).count == 2 }
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.of(Players.first)[1].starts.map(\.takingOverPause) == [true])
    }

    @MainActor
    @Test("a held pause ends once its player plays again: its monitoring stops")
    func heldPauseEnds() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let held = bench.monitorings.of(Players.first)[0]
        held.send(.activeSources([Self.vlc])) // its own: not the session's state
        #expect(session.state.activeSources.isEmpty)
        held.send(.playback(.musicPlaying))
        await TestWait.until { held.isStopped }
        #expect(!session.isHoldingPause)
    }

    @MainActor
    @Test("a pause handed over by the AutoHush before is taken over once, and only when recent")
    func pauseHandover() async {
        let bench = Bench()
        // Handed over after launch, as a copy that quits for this one does.
        bench.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: nil)
        let session = await bench.started()
        #expect(bench.monitorings.made[0].starts.map(\.takingOverPause) == [true])
        #expect(bench.preferences.pauseHandover == nil) // read once

        bench.preferences.pauseHandover = PauseHandover(at: Date(), player: nil)
        session.retry() // only the first monitoring takes one over
        await TestWait.until { bench.monitorings.made.count == 2 }
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.made[1].starts.map(\.takingOverPause) == [false])

        let stale = Bench()
        stale.preferences.pauseHandover = PauseHandover(
            at: Date().addingTimeInterval(-(PlayerSession.pauseHandoverMaxAge + 1)), player: nil
        )
        _ = await stale.started()
        #expect(stale.monitorings.made[0].starts.map(\.takingOverPause) == [false])

        let none = Bench()
        _ = await none.started()
        #expect(none.monitorings.made[0].starts.map(\.takingOverPause) == [false])
    }

    @MainActor
    @Test("a start asked for before launch (the player opened, Try Again, another chosen) waits for it: then it starts, taking the pause handed over")
    func startWaitsForLaunch() async {
        let bench = Bench()
        let session = bench.makeSession(bench.second)
        // While the copies opened before it quit, handing their pause over.
        session.playerLaunched(Players.second)
        session.retry()
        session.choose(bench.first)
        await session.waitUntilIdle()
        #expect(bench.monitorings.made.isEmpty)
        #expect(await bench.first.verifyCallCount == 0)

        bench.preferences.pauseHandover = PauseHandover(at: Date(), player: Players.first)
        session.launch()
        await TestWait.until { session.state.health == .ready }
        #expect(bench.monitorings.made.map(\.bundleID) == [Players.first])
        #expect(bench.monitorings.made[0].starts.map(\.takingOverPause) == [true])
    }

    @MainActor
    @Test("a pause handed over for another player than the one chosen now isn't taken over")
    func pauseHandoverForAnotherPlayer() async {
        let other = Bench()
        // The player was changed outside the app meanwhile.
        other.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: Players.second)
        _ = await other.started()
        #expect(other.monitorings.made[0].starts.map(\.takingOverPause) == [false])
        #expect(other.preferences.pauseHandover == nil)

        let same = Bench()
        same.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: Players.first)
        _ = await same.started()
        #expect(same.monitorings.made[0].starts.map(\.takingOverPause) == [true])
    }

    @MainActor
    @Test("quitting while holding a pause hands it over for the chosen player, and stops monitoring with the volume back")
    func pauseHandedOverOnQuit() async {
        let bench = Bench()
        let session = await bench.started()
        let monitoring = bench.monitorings.made[0]
        monitoring.send(.playback(.pausedByMonitor))

        let stopping = session.quit()
        #expect(bench.preferences.pauseHandover?.player == Players.first)
        #expect(bench.preferences.pauseHandover?.holdsChosen == true)
        await stopping?.value
        #expect(monitoring.restoredStops == 1)
    }

    @MainActor
    @Test("with nothing running, quitting hands nothing over and doesn't wait")
    func quitWithNothingRunning() {
        let bench = Bench()
        let session = bench.makeSession(bench.first)
        #expect(session.quit() == nil)
        #expect(bench.preferences.pauseHandover == nil)
    }

    @MainActor
    @Test("a start under way as AutoHush quits gives up, and nothing starts after: no monitoring outlives the quit")
    func quitDuringStart() async {
        let bench = Bench()
        let checking = ManualSleep() // holds the start at its access check
        await bench.first.setBeforeVerify { await checking.sleep(.zero) }
        let session = bench.makeSession(bench.first)
        session.launch()
        await TestWait.until { checking.durations.count == 1 }

        #expect(session.quit() == nil) // nothing runs yet
        checking.timeIsUp()
        session.retry()
        session.playerLaunched(Players.first)
        await session.waitUntilIdle()
        #expect(bench.monitorings.made.isEmpty)
        #expect(await bench.first.verifyCallCount == 1)
    }

    @MainActor
    @Test("quitting with players held paused hands those over too, with or without the chosen one's pause")
    func heldPausesHandedOverOnQuit() async {
        let bench = Bench()
        let session = await bench.holdingFirst()
        let stopping = session.quit()
        #expect(bench.preferences.pauseHandover?.held == [Players.first])
        #expect(bench.preferences.pauseHandover?.holdsChosen == false)
        await stopping?.value
        #expect(bench.monitorings.of(Players.first)[0].restoredStops == 1)

        let both = Bench()
        let session2 = await both.holdingFirst()
        both.monitorings.of(Players.second)[0].send(.playback(.pausedByMonitor)) // the chosen one paused too
        _ = session2.quit()
        #expect(both.preferences.pauseHandover?.player == Players.second)
        #expect(both.preferences.pauseHandover?.holdsChosen == true)
        #expect(both.preferences.pauseHandover?.held == [Players.first])
    }

    @MainActor
    @Test("players held paused when the AutoHush before quit are handed over: the others' monitoring starts at launch, the chosen one takes its own back")
    func heldPausesHandedOverOnLaunch() async {
        let bench = Bench()
        bench.monitorings.findPauses = true
        bench.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: nil,
                                                        holdsChosen: false, held: [Players.second])
        _ = await bench.started()
        await TestWait.until { !bench.monitorings.of(Players.second).isEmpty }
        let held = bench.monitorings.of(Players.second)[0]
        await TestWait.until { !held.starts.isEmpty }
        #expect(held.starts.map(\.takingOverPause) == [true])
        #expect(!held.isStopped) // it found its pause: it runs on
        #expect(bench.monitorings.of(Players.first)[0].starts.map(\.takingOverPause) == [false]) // the chosen one wasn't paused

        let back = Bench()
        back.monitorings.findPauses = true
        back.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: nil,
                                                       holdsChosen: false, held: [Players.first, Players.second])
        _ = await back.started()
        #expect(back.monitorings.of(Players.second).count == 1)
        #expect(back.monitorings.of(Players.first)[0].starts.map(\.takingOverPause) == [true]) // chosen again since: its own pause back

        let gone = Bench() // played or quit meanwhile: nothing to end
        gone.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-5), player: nil,
                                                       holdsChosen: false, held: [Players.second])
        _ = await gone.started()
        await TestWait.until { gone.monitorings.of(Players.second).first?.isStopped == true }
        #expect(gone.monitorings.of(Players.second)[0].isStopped)

        let stale = Bench()
        stale.preferences.pauseHandover = PauseHandover(at: Date().addingTimeInterval(-(PlayerSession.pauseHandoverMaxAge + 1)),
                                                        player: nil, holdsChosen: false, held: [Players.second])
        _ = await stale.started()
        #expect(stale.monitorings.of(Players.second).isEmpty)
    }
}
