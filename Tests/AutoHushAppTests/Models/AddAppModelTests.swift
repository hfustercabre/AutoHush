import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

@MainActor
@Suite("AddAppModel", .timeLimit(.minutes(1)))
struct AddAppModelTests {
    private let result = CheckResult(
        ways: [CheckResult.WayResult(kind: .menu, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
        setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                           ways: [.panel(rememberedRow: nil)]))

    /// A model at its first step, its window open, its apps read.
    private func model(_ world: World) async -> AddAppModel {
        let model = AddAppModel(services: world.services)
        model.reset()
        await model.loadApps()
        return model
    }

    @Test("the app playing in Now Playing is picked; the others that can play come after those in Now Playing")
    func choosing() async {
        let world = World()
        let model = await model(world)
        #expect(model.selectedID == "com.example.player")
        #expect(model.shownApps.inNowPlaying.map(\.name) == ["Player"])
        #expect(model.shownApps.others.map(\.name) == ["Other"])
        model.search = "oth"
        #expect(model.shownApps.inNowPlaying.isEmpty && model.shownApps.others.map(\.name) == ["Other"])
        #expect(model.steps == [.choose, .allow, .play, .check, .use])
        #expect(model.mark(of: .choose) == .current && model.mark(of: .allow) == .todo)
    }

    @Test("choosing in the list, or an app picked on the disk, goes on; Change… starts over with the list")
    func chooser() async {
        let world = World()
        let model = await model(world)
        model.openChooser()
        #expect(world.choosers == 1)
        model.chooseOther(at: URL(filePath: "/Applications/AutoHush.app"))
        #expect(model.otherAppProblem == .autoHush && model.stage == .choosing)
        model.chooseOther(at: URL(filePath: "/Applications/Picked.app"))
        #expect(model.chosen?.bundleID == "com.example.picked" && model.apps.contains { $0.bundleID == "com.example.picked" })
        await TestWait.until { model.canChangeApp } // past opening it
        model.changeApp()
        #expect(model.stage == .choosing && model.chosen == nil && world.choosers == 2)
        model.choose(world.apps[1])
        #expect(model.chosen?.bundleID == "com.example.other")
    }

    @Test("an app that isn't open is opened, with its launch option when it needs one")
    func opening() async {
        let world = World()
        world.running = false
        world.traits.needsLaunchOption = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.currentStep != .choose }
        #expect(world.opened.map(\.1) == [true])
        #expect(!model.needsReopen)
    }

    @Test("permissions are watched until all are allowed; then it waits for the app to play, and it's ready once it plays")
    func permissionsThenPlaying() async {
        let world = World()
        world.permissions.accessibility = false
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.accessibility == false }
        #expect(model.mark(of: .allow) == .current)
        world.permissions.accessibility = true
        await TestWait.until { model.currentStep == .play }
        #expect(model.mark(of: .allow) == .done)
        world.playing = true
        await TestWait.until { model.stage == .ready }
        #expect(model.mark(of: .check) == .current)
    }

    @Test("without Audio Recording it waits, then Continue goes on; without Accessibility it can't")
    func optionalPermissions() async {
        let world = World()
        world.permissions = CheckPermissions(accessibility: false, audio: .denied)
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.audio == .denied }
        #expect(!model.permissions.neededAllowed && model.permissions.missingOptional(antiDot: false) == [.audioRecording])
        model.continueWithoutAll()
        #expect(model.stage == .allowing)
        world.permissions.accessibility = true
        await TestWait.until { model.permissions.neededAllowed }
        #expect(model.stage == .allowing) // not everything is allowed: it waits for Continue
        model.continueWithoutAll()
        #expect(model.currentStep == .play)
    }

    @Test("an app that can be scripted needs Automation too")
    func automation() async {
        let world = World()
        world.traits.scriptable = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.permissions.automation == .notAsked }
        #expect(model.stage == .allowing)
        world.permissions.automation = .allowed
        await TestWait.until { model.currentStep == .play }
    }

    @Test("an Electron app opened without its option asks before reopening; Skip goes on without")
    func reopening() async {
        let world = World()
        world.traits.needsLaunchOption = true
        world.runsWithOption = false
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .reopenAsked }
        #expect(model.steps.contains(.reopen) && world.reopened == 0)
        model.reopen()
        await TestWait.until { model.currentStep == .play }
        #expect(world.reopened == 1 && model.reopenOutcome == .reopened)

        let other = World()
        other.traits.needsLaunchOption = true
        other.runsWithOption = false
        let skipping = await self.model(other)
        skipping.continueWithApp()
        await TestWait.until { skipping.stage == .reopenAsked }
        skipping.skipReopen()
        #expect(skipping.reopenOutcome == .skipped && skipping.currentStep == .play && other.reopened == 0)
    }

    @Test("it gives up waiting for the app to play after 2 minutes; Try Again waits again")
    func playTimeout() async {
        let world = World()
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.currentStep == .play }
        world.now = world.now.addingTimeInterval(AddAppModel.playWait)
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.mark(of: .play) == .failed)
        world.playing = true
        model.waitForPlaying()
        await TestWait.until { model.stage == .ready }
    }

    /// A model ready for its check.
    private func ready(_ world: World) async -> AddAppModel {
        world.playing = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .ready }
        return model
    }

    @Test("Continue… shows the warning; its Start runs the check with its panel; what it found ends at Use")
    func checking() async {
        let world = World()
        let model = await ready(world)
        model.continueToCheck()
        #expect(world.warnings == 1 && model.stage == .ready)
        model.startCheck()
        #expect(model.stage == .checking && model.mark(of: .check) == .busy)
        await TestWait.until { world.panel == ["shown"] }
        #expect(model.progress.stage == .testing && world.taps == [true])
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        #expect(world.panel == ["shown", "hidden"])
        #expect(model.mark(of: .check) == .done && model.mark(of: .use) == .current)
        model.use()
        #expect(world.used == [result] && world.closed == 1 && world.asksToReopen == [true])
    }

    @Test("only the ways that worked, fully or partly, can be chosen; the first is recommended and used unless another is chosen, and only the chosen one is kept")
    func choosingTheWay() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        let found = CheckResult(
            ways: [CheckResult.WayResult(kind: .script, mark: .notThere), CheckResult.WayResult(kind: .menu, mark: .some, failedStates: [.hidden]),
                   CheckResult.WayResult(kind: .page, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback"), .panel(rememberedRow: nil)]))
        world.run.finish(.finished(found))
        await TestWait.until { model.result != nil }
        #expect(model.choosableWays == [.menu, .panel] && model.chosenWay == .menu)
        model.choose(.page)
        #expect(model.chosenWay == .menu)
        model.choose(.panel)
        #expect(model.chosenWay == .panel)
        model.use()
        #expect(world.used.first?.setup?.ways == [.panel(rememberedRow: nil)] && world.used.first?.ways == found.ways)
    }

    @Test("a stopped check can run again; a check that found no way says so")
    func stoppedAndNothing() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.stopCheck()
        await TestWait.until { model.stage == .stopped }
        #expect(world.run.stopped && model.mark(of: .check) == .failed)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }

        let none = World()
        let empty = await ready(none)
        empty.startCheck()
        await TestWait.until { none.panel == ["shown"] }
        none.run.finish(.finished(CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .notThere)], setup: nil)))
        await TestWait.until { empty.result != nil }
        #expect(empty.mark(of: .use) == .failed)
        empty.use()
        #expect(none.used.isEmpty)
    }

    @Test("a permission the check found missing goes back to asking for it")
    func permissionMissing() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.permissions.audio = .denied
        world.run.finish(.permissionMissing)
        await TestWait.until { model.stage == .allowing }
        #expect(model.permissionMissingInCheck)
    }

    @Test("when no way worked it can be muted instead, with Audio Recording: the app is kept to be muted, never paused")
    func muteInstead() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.permissions.audio = .denied
        world.run.finish(.finished(CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .none)], setup: nil)))
        await TestWait.until { model.result != nil && !model.canMute }
        model.useMuting()
        #expect(world.used.isEmpty)
        world.permissions.audio = .allowed
        model.allowMuting()
        await TestWait.until { model.canMute }
        model.useMuting()
        #expect(world.used.first?.setup?.ways == [.mute] && world.closed == 1)
    }

    @Test("closing the window stops the check")
    func closing() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.windowClosed()
        #expect(world.run.stopped)
        await TestWait.until { world.panel == ["shown", "hidden"] }
    }

    @Test("closing the window closes the warning, and its Start then runs nothing")
    func closingWithTheWarning() async {
        let world = World()
        let model = await ready(world)
        model.continueToCheck()
        model.windowClosed()
        #expect(world.warningsClosed == 1)
        model.startCheck()
        #expect(model.stage == .ready && world.runs == 0)
    }

    @Test("a check stopped by closing the window puts things back before the next starts; its end hides the panel only then")
    func overlappingChecks() async {
        let world = World()
        let model = await ready(world)
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
    }

    @Test("the app quitting while it's waited for says so; Open opens it and waits again")
    func appQuits() async {
        let world = World()
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.currentStep == .play }
        world.running = false
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.appQuit && model.mark(of: .play) == .failed)
        model.openAppAgain()
        await TestWait.until { model.currentStep == .play && !model.appQuit }
        #expect(world.opened.count == 1)
    }

    @Test("a check that couldn't finish says why: the app quit, it's gone, or the log")
    func failureReasons() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.running = false
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }
        #expect(model.failureReason == .appQuit)

        let other = World()
        let failing = await ready(other)
        failing.startCheck()
        await TestWait.until { other.panel == ["shown"] }
        other.run.finish(.failed(1))
        await TestWait.until { failing.stage == .failed }
        #expect(failing.failureReason == .other)
    }

    @Test("a finished check is kept until it's used: the window opened again shows it")
    func keptResult() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        model.windowClosed()
        let again = AddAppModel(services: world.services)
        again.reset()
        #expect(again.result == result && again.chosen?.bundleID == "com.example.player")
        again.use()
        #expect(world.kept.load() == nil && world.used == [result])
    }

    @Test("with Now Playing hidden in the menu bar, Check Again is offered beside Use and checks again")
    func panelHidden() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .works), CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback")]))))
        await TestWait.until { model.result != nil }
        #expect(model.offersCheckAgain && model.mark(of: .use) == .current)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
    }

    @Test("after Skip at the Reopen step, Use doesn't ask to reopen it, also once the kept check is restored")
    func skippedReopen() async {
        let world = World()
        world.traits.needsLaunchOption = true
        world.runsWithOption = false
        world.playing = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .reopenAsked }
        model.skipReopen()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        model.windowClosed()
        let again = AddAppModel(services: world.services)
        again.reset()
        #expect(again.steps.contains(.reopen) && again.reopenOutcome == .skipped)
        again.use()
        #expect(world.asksToReopen == [false])
    }

    @Test("AntiDot mode: Audio Recording isn't asked for or missed, the check taps nothing, and neither muting nor a panel only its sound tells can be used")
    func antiDot() async {
        let world = World()
        world.antiDot = true
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        world.playing = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .ready } // all it uses is allowed
        #expect(model.permissions.missingOptional(antiDot: true).isEmpty)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        #expect(world.taps == [false])
        world.permissions.audio = .allowed
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .notThere), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)], panelRowIsStale: true))))
        await TestWait.until { model.result != nil }
        #expect(!model.canMute && model.choosableWays.isEmpty && model.mark(of: .use) == .failed && model.offersCheckAgain)
        model.use()
        #expect(world.used.isEmpty)
    }

    @Test("Audio Recording turned on in System Settings waits for AutoHush to reopen")
    func audioAfterReopen() async {
        let world = World()
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.audio == .denied }
        #expect(!model.audioAwaitsReopen)
        model.request(.audioRecording)
        #expect(model.audioAwaitsReopen)
    }
}
