import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension PlayerSessionTests {
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
        monitoring.send(.activeSources([Self.viewer]))
        monitoring.send(.learnedAssertions(Self.viewer.id, AnnouncedAssertions(system: ["Playing audio"])))
        #expect(session.state.playback == .pausedByMonitor)
        #expect(session.state.detection == .audioLevel)
        #expect(session.state.activeSources == [Self.viewer])
        #expect(bench.preferences.seenApps.map(\.id) == [Self.viewer.id])
        #expect(bench.preferences.playbackAssertions[Self.viewer.id] == AnnouncedAssertions(system: ["Playing audio"]))
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
        session.playerLaunched("org.example.viewer")
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
        listening[0].send(.activeSources([Self.viewer]))
        #expect(session.state.activeSources == [Self.viewer]) // listed
        #expect(session.state.health == .playerClosed("Second isn’t running")) // still says so
    }

    @MainActor
    @Test("while the player isn't running, Auto-Pause off stops listing the apps until it's on again")
    func autoPauseOffStopsListing() async {
        let bench = Bench()
        let session = await bench.secondNotRunning()
        let listening = bench.monitorings.of(Players.second)
        listening[0].send(.activeSources([Self.viewer]))

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
        bench.monitorings.made[0].send(.learnedAssertions(Self.viewer.id, AnnouncedAssertions(system: ["Playing audio"])))
        #expect(session.state.controlError == nil)
        #expect(bench.preferences.playbackAssertions[Self.viewer.id] == AnnouncedAssertions(system: ["Playing audio"]))
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
}
