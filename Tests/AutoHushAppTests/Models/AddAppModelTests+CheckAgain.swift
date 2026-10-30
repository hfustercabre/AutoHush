import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import WebAppPlayers

extension AddAppModelTests {
    @Test("a finished check is kept until it's used: the window opened again shows it")
    func keptResult() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        model.windowClosed()
        let again = AddAppModel(world)
        again.reset()
        #expect(again.result == result && again.chosen?.bundleID == "com.example.player")
        again.use()
        #expect(world.kept.load() == nil && world.used == [result])
    }

    @Test("with Now Playing hidden in the menu bar, Check Again is offered beside Use and checks again")
    func panelHidden() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback")]))))
        await TestWait.until { model.result != nil }
        #expect(model.offersCheckAgain && model.state(of: .use) == .current && model.nowPlayingHidden)
        model.openMenuBarSettings()
        #expect(world.menuBarSettingsOpened == 1)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
    }

    @Test("checked with its windows closed, Check Again is offered beside Use only while a way didn't work or wasn't checked",
          arguments: [(CheckResult.Mark.none, true), (.noWindow, true), (.notThere, false)])
    func windowsClosed(other: CheckResult.Mark, offered: Bool) async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: other), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)]),
            windowsClosed: true)))
        await TestWait.until { model.result != nil }
        #expect(model.state(of: .use) == .current && model.offersCheckAgain == offered)
        model.checkAgain()
        if offered { await TestWait.until { model.stage == .ready } } else { #expect(model.stage == .done(model.result!)) }
    }

    @Test("after Check Again beside Use, Back to Result brings the last result back until the new check starts: while it waits to play, and once it's ready")
    func backToResult() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        let closed = CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)]),
            windowsClosed: true)
        world.run.finish(.finished(closed))
        await TestWait.until { model.result != nil }
        #expect(!model.canGoBackToResult)

        world.playing = false
        model.checkAgain()
        #expect(model.result == nil && model.canGoBackToResult) // waiting for it to play
        model.backToResult()
        #expect(model.result == closed && !model.canGoBackToResult && model.state(of: .use) == .current)

        world.playing = true
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        #expect(model.canGoBackToResult)
        model.startCheck() // the new check started: no going back but by Stop
        #expect(!model.canGoBackToResult)
    }

    @Test("after Check Again beside Use, Change… asks before forgetting the result Back to Result would bring back; Back to Result is gone with the app moved, and stays once it quits")
    func backToResultEdges() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)]),
            windowsClosed: true)))
        await TestWait.until { model.result != nil }

        world.playing = false
        model.checkAgain()
        #expect(model.result == nil && model.changeAppForgetsCheck)
        world.exists = false
        #expect(!model.canGoBackToResult)
        world.exists = true
        world.running = false
        await TestWait.until { model.appQuit }
        #expect(model.stage == .playTimedOut && model.canGoBackToResult)
    }

    @Test("after Check Again following a check with its windows closed, the play step waits for a window too; Back to Result forgets the wait")
    func checkAgainWaitsForWindow() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .page, mark: .noWindow), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)]),
            windowsClosed: true)))
        await TestWait.until { model.result != nil }

        world.playing = true
        world.windowOpen = false
        model.checkAgain()
        await TestWait.until { model.windowMissing }
        #expect(model.stage != .ready) // playing, but no window yet
        world.windowOpen = true
        await TestWait.until { model.stage == .ready }
        #expect(!model.windowMissing)

        model.backToResult()
        #expect(!model.waitsForWindow)
    }

    @Test("Check Again beside Use for Now Playing hidden (windows open) doesn't wait for a window")
    func checkAgainNoWindowWait() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback")]))))
        await TestWait.until { model.result != nil }
        world.playing = true
        world.windowOpen = false
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        #expect(!model.waitsForWindow && !model.windowMissing)
    }

    @Test("Check Again beside Use that doesn't finish (stopped, or failed) brings the kept result back, Use with it", arguments: [true, false])
    func checkAgainUnfinished(stopped: Bool) async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback")]))))
        await TestWait.until { model.result != nil }
        let result = model.result
        world.run = FakeCheckRun()
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 2 }
        world.run.finish(stopped ? .stopped : .failed(1))
        await TestWait.until { model.result != nil }
        #expect(model.result == result && model.state(of: .use) == .current)

        // Gone from the disk meanwhile: no Use for it, but why, with Change….
        world.run = FakeCheckRun()
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 3 }
        world.exists = false
        world.running = false
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }
        #expect(model.result == nil && model.failureReason == .appNotFound)
    }

    @Test("Check Again beside Use that ends with the app quit (nothing could be tried) brings the kept result back, Use with it, as one that doesn't finish does")
    func checkAgainAppQuit() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback")]))))
        await TestWait.until { model.result != nil }
        let result = model.result
        world.run = FakeCheckRun()
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 2 }
        world.running = false
        world.run.finish(.finished(CheckResult(ways: [], setup: nil)))
        await TestWait.until { model.result != nil }
        #expect(model.result == result && model.state(of: .use) == .current && model.failureReason == nil)
    }

    @Test("permissions read for an app no longer chosen once they come never show: the app chosen meanwhile has its own")
    func permissionsOfAnotherApp() async throws {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        let chosen = try #require(model.chosen)
        let other = try #require(world.apps.first { $0 != chosen })
        world.permissions.accessibility = false
        await model.refreshPermissions(for: other, scriptable: false)
        #expect(model.permissions.accessibility) // the chosen app's, as read before
        await model.refreshPermissions(for: chosen, scriptable: false)
        #expect(!model.permissions.accessibility)
    }

    @Test("after Skip at the Reopen step, Use doesn't ask to reopen it, also once the kept check is restored")
    func skippedReopen() async {
        let world = World()
        world.traits.needsLaunchOption = true
        world.runsWithOption = false
        world.playing = true
        let model = await AddAppModel.opened(on: world)
        model.continueWithApp()
        await TestWait.until { model.stage == .reopenAsked }
        model.skipReopen()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        model.windowClosed()
        let again = AddAppModel(world)
        again.reset()
        #expect(again.steps.contains(.reopen) && again.reopenOutcome == .skipped)
        again.use()
        #expect(world.asksToReopen == [false])
    }
}
