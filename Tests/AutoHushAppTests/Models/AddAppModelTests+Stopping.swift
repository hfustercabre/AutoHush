import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import WebAppPlayers

extension AddAppModelTests {
    @Test("closing the window stops the check")
    func closing() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.windowClosed()
        #expect(world.run.stopped)
        await TestWait.until { world.panel == ["shown", "hidden"] }
    }

    @Test("closing the window closes the warning, and its Start then runs nothing")
    func closingWithTheWarning() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.continueToCheck()
        model.windowClosed()
        #expect(world.warningsClosed == 1)
        model.startCheck()
        #expect(model.stage == .ready && world.runs == 0)
    }

    @Test("a check stopped by closing the window puts things back before the next starts; its end hides the panel only then")
    func overlappingChecks() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        let first = world.run
        first.endsWhenStopped = false
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.windowClosed()
        #expect(first.stopped && model.isEndingLastCheck)
        // Opened again, the next check waits for the first.
        world.run = FakeCheckRun()
        model.reset()
        await model.loadApps()
        model.continueWithApp()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await Task.yield()
        #expect(model.stage == .checking && world.runs == 1)
        first.finish(.stopped)
        await TestWait.until { world.runs == 2 }
        await TestWait.until { !model.isEndingLastCheck }
        #expect(world.panel.filter { $0 == "shown" }.count == 2 && world.panel.last == "shown")
        world.run.finish(.stopped) // else its task waits for good, keeping the model and the world
    }

    @Test("Stop while the last check still puts things back: the new one never starts, back to its step, the app watched until Start again")
    func stopWhileLastCheckEnds() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        let first = world.run
        first.endsWhenStopped = false
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.windowClosed()
        world.run = FakeCheckRun()
        model.reset()
        await model.loadApps()
        model.continueWithApp()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await Task.yield()
        #expect(model.stage == .checking && model.isEndingLastCheck)
        model.stopCheck() // the window's Stop, or Escape
        #expect(model.stage == .ready)
        first.finish(.stopped)
        await TestWait.until { !model.isEndingLastCheck }
        #expect(world.runs == 1 && model.stage == .ready)
        world.running = false // still watched until Start (WA2)
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.appQuit)
    }

    @Test("Change… closes the warning before a check: its Start was for the app before")
    func changeClosesWarning() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.continueToCheck()
        let closed = world.warningsClosed
        model.changeApp()
        #expect(world.warningsClosed == closed + 1)
    }

    @Test("the app quitting while it's waited for says so; Open opens it (its step busy, the steps before still done) and waits again, or says so again when it doesn't open")
    func appQuits() async {
        let world = World()
        let model = await AddAppModel.opened(on: world)
        model.continueWithApp()
        await TestWait.until { model.currentStep == .play }
        world.running = false
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.appQuit && model.state(of: .play) == .failed)
        world.opens = false
        model.openAppAgain()
        #expect(model.stage == .openingAgain && !model.appQuit)
        #expect(model.isBusy(.play) && [.choose, .allow].allSatisfy { model.state(of: $0) == .done })
        await TestWait.until { model.appQuit }
        #expect(model.stage == .playTimedOut && world.opened.count == 1)
        world.opens = true
        model.openAppAgain()
        await TestWait.until { model.stage == .waitingToPlay(since: world.now) }
        #expect(!model.appQuit && world.opened.count == 2)
    }

    @Test("the app quitting once it plays, before the check starts, says so at once, the warning before the check closed")
    func appQuitsWhenReady() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.continueToCheck()
        let closed = world.warningsClosed
        world.running = false
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.appQuit && model.state(of: .play) == .failed)
        #expect(world.warningsClosed == closed + 1)
    }

    @Test("the app quitting and no longer found (moved or deleted) while it's waited for, or in the check, offers another app instead of Open or Check Again")
    func appGone() async {
        let world = World()
        let model = await AddAppModel.opened(on: world)
        model.continueWithApp()
        await TestWait.until { model.currentStep == .play }
        world.running = false
        world.exists = false
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.appQuit && model.appNotFound && model.canChangeApp)
        model.openAppAgain() // nothing to open
        #expect(model.stage == .playTimedOut && world.opened.isEmpty)
        model.changeApp()
        #expect(model.stage == .choosing && !model.appNotFound)

        let checked = World()
        let ready = await AddAppModel.ready(on: checked)
        ready.startCheck()
        await TestWait.until { checked.panel == ["shown"] }
        checked.exists = false
        checked.run.finish(.failed(1))
        await TestWait.until { ready.stage == .failed }
        #expect(ready.failureReason == .appNotFound && ready.appNotFound && ready.canChangeApp)
    }

    @Test("Stop (the window's, Escape or the panel's) says it's stopping, its button off, until the check has put things back")
    func stopping() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        world.run.endsWhenStopped = false
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        #expect(!model.isStopping)
        model.stopCheck()
        #expect(model.isStopping && model.stage == .checking && world.run.stopped)
        world.run.finish(.stopped)
        await TestWait.until { model.stage == .stopped }
        #expect(!model.isStopping)
    }

    @Test("a check that couldn't finish says why: the app quit (its result empty too), it's gone, or the log, also when none could start")
    func failureReasons() async {
        /// Why a check that ends with `end` couldn't finish, `change` made to the world first.
        func reason(_ end: PlayerCheckEnd, _ change: (World) -> Void = { _ in }) async -> PlayerCheckEnd.Reason? {
            let world = World()
            let model = await AddAppModel.ready(on: world)
            model.startCheck()
            await TestWait.until { world.panel == ["shown"] }
            change(world)
            world.run.finish(end)
            await TestWait.until { model.stage == .failed }
            return model.failureReason
        }
        #expect(await reason(.failed(1)) { $0.running = false } == .appQuit)
        // Quit, nothing could be tried: not "no way worked", with Mute It Instead.
        #expect(await reason(.finished(CheckResult(ways: [], setup: nil))) { $0.running = false } == .appQuit)
        #expect(await reason(.failed(1)) { $0.exists = false } == .appNotFound)
        #expect(await reason(.failed(1)) == .other)

        // The helper couldn't start one; Show Log… once there's a log.
        let world = World()
        world.startsCheck = false
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { model.stage == .failed }
        #expect(model.failureReason == .other && world.panel.isEmpty && !model.canShowLog)
        world.hasLog = true
        model.showLog()
        #expect(model.canShowLog && world.logsShown == 1)
    }
}
