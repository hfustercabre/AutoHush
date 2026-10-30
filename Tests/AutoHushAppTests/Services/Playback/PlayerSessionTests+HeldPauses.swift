import Foundation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

extension PlayerSessionTests {
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
        held.send(.activeSources([Self.viewer])) // its own: not the session's state
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
