import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import WebAppPlayers
import PlayerCheckKit

@MainActor
@Suite("AddAppModel", .waitsTimeLimit)
struct AddAppModelTests {
    private let result = CheckResult(
        ways: [CheckResult.WayResult(kind: .menu, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
        setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                           ways: [.panel(rememberedRow: nil)]))

    /// A model at its first step, its window open, its apps read.
    private func model(_ world: World) async -> AddAppModel {
        let model = AddAppModel(world)
        model.reset()
        await model.loadApps()
        return model
    }

    @Test("the app playing in Now Playing is picked, or the only one there; the others that can play come after those in Now Playing")
    func choosing() async {
        let world = World()
        let model = await model(world)
        #expect(model.selectedID == "com.example.player")
        #expect(model.shownApps.inNowPlaying.map(\.name) == ["Player"])
        #expect(model.shownApps.others.map(\.name) == ["Other"])
        model.search = "oth"
        #expect(model.shownApps.inNowPlaying.isEmpty && model.shownApps.others.map(\.name) == ["Other"])
        #expect(model.steps == [.choose, .allow, .play, .check, .use] && model.number(of: .play) == 3)
        #expect(model.state(of: .choose) == .current && model.state(of: .allow) == .todo)
        #expect(!model.canChangeApp) // nothing chosen yet

        // In the list's order, those in Now Playing first: the only one there is picked, playing or not.
        let paused = World()
        paused.apps[0].nowPlaying = false
        #expect(await self.model(paused).selectedID == "com.example.player")
        let none = World()
        none.apps[0].nowPlaying = nil
        #expect(await self.model(none).selectedID == nil)
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

    @Test("another app selected in the list drops Other App…'s warning, which was about the app picked on the disk")
    func selectionDropsOtherAppWarning() async {
        let world = World()
        let model = await model(world)
        model.openChooser()
        model.chooseOther(at: URL(filePath: "/Applications/AutoHush.app"))
        #expect(model.otherAppProblem == .autoHush)
        model.selectedID = world.apps[1].id
        #expect(model.otherAppProblem == nil)
    }

    @Test("an app that isn't open is opened, with its launch option when it needs one; one that doesn't open says so, back at the first step")
    func opening() async {
        let world = World()
        world.running = false
        world.traits.needsLaunchOption = true
        let model = await model(world)
        model.continueWithApp()
        #expect(model.stage == .opening && !model.canChangeApp)
        await TestWait.until { model.currentStep != .choose }
        #expect(world.opened.map(\.1) == [true])
        #expect(!model.needsReopen)

        let failing = World()
        failing.running = false
        failing.opens = false
        let unopened = await self.model(failing)
        unopened.continueWithApp()
        await TestWait.until { unopened.openFailed }
        #expect(unopened.stage == .choosing && failing.opened.count == 1 && unopened.canContinueWithApp)
    }

    @Test("permissions are watched until all are allowed; then it waits for the app to play, and it's ready once it plays")
    func permissionsThenPlaying() async {
        let world = World()
        world.permissions.accessibility = false
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.accessibility == false }
        #expect(model.state(of: .allow) == .current)
        world.permissions.accessibility = true
        await TestWait.until { model.currentStep == .play }
        #expect(model.state(of: .allow) == .done)
        world.playing = true
        await TestWait.until { model.stage == .ready }
        #expect(model.state(of: .check) == .current)
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

    @Test("an Electron app opened without its option asks before reopening, again when it didn't quit; Skip goes on without")
    func reopening() async {
        let world = World()
        world.traits.needsLaunchOption = true
        world.runsWithOption = false
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .reopenAsked }
        #expect(model.steps.contains(.reopen) && world.reopened == 0)
        #expect(model.number(of: .reopen) == 3 && model.number(of: .play) == 4 && model.canChangeApp)
        world.reopens = false // it didn't quit
        model.reopen()
        #expect(model.stage == .reopening && !model.canChangeApp)
        await TestWait.until { model.reopenFailed }
        #expect(model.stage == .reopenAsked && world.reopened == 1)
        world.reopens = true
        model.reopen()
        #expect(!model.reopenFailed)
        await TestWait.until { model.currentStep == .play }
        #expect(world.reopened == 2 && model.reopenOutcome == .reopened)

        let other = World()
        other.traits.needsLaunchOption = true
        other.runsWithOption = false
        let skipping = await self.model(other)
        skipping.continueWithApp()
        await TestWait.until { skipping.stage == .reopenAsked }
        skipping.skipReopen()
        #expect(skipping.reopenOutcome == .skipped && skipping.currentStep == .play && other.reopened == 0)
    }

    @Test("it gives up waiting for the app to play after 2 minutes, as the window says; Try Again waits again")
    func playTimeout() async {
        let world = World()
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.currentStep == .play }
        world.now = world.now.addingTimeInterval(AddAppModel.playWait)
        await TestWait.until { model.stage == .playTimedOut }
        #expect(model.state(of: .play) == .failed)
        let minutes = "\(Int(AddAppModel.playWait / 60)) minutes"
        #expect(AddAppText.playWaits.contains(minutes) && AddAppText.didNotPlay("Player").contains(minutes))
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
        #expect(world.warnings == 1 && model.stage == .ready && model.canChangeApp)
        model.startCheck()
        #expect(model.stage == .checking && model.isBusy(.check) && !model.canChangeApp)
        await TestWait.until { world.panel == ["shown"] }
        #expect(model.progress.stage == .testing && world.taps == [true])
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        #expect(world.panel == ["shown", "hidden"])
        #expect(model.state(of: .check) == .done && model.state(of: .use) == .current && !model.nowPlayingHidden)
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

    @Test("Change… asks first once the check has run, since it forgets what was found; not before")
    func changeAsksAfterTheCheck() async {
        let world = World()
        let model = await ready(world)
        #expect(model.canChangeApp && !model.changeAppForgetsCheck)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(CheckResult(ways: [CheckResult.WayResult(kind: .panel, mark: .works)],
                                               setup: PlayerSetup(bundleID: "com.example.player", name: "Player",
                                                                  appURL: URL(filePath: "/Applications/Player.app"),
                                                                  ways: [.panel(rememberedRow: nil)]))))
        await TestWait.until { model.result != nil }
        #expect(model.canChangeApp && model.changeAppForgetsCheck)
        model.changeApp()
        #expect(model.stage == .choosing && !model.changeAppForgetsCheck)
    }

    @Test("the check mutes the app, with Audio Recording allowed outside AntiDot mode")
    func checkMuting() async {
        let world = World()
        let model = await ready(world)
        #expect(model.checkMuting == .app)
    }

    @Test("the check mutes the Mac's output in AntiDot mode, as read with the permissions")
    func checkMutingInAntiDot() async {
        let world = World()
        let model = await ready(world)
        world.antiDot = true
        #expect(model.checkMuting == .mac) // as read with the permissions
    }

    @Test("whether the Mac can mute isn't read again each time what the check mutes is drawn")
    func checkMutingNotReadAtDrawing() async {
        let world = World()
        let model = await ready(world)
        world.antiDot = true
        let reads = world.macCanMuteReads
        world.macCanMute = false // another output chosen meanwhile
        #expect(model.checkMuting == .mac && model.checkMuting == .mac) // drawn again: as read
        #expect(world.macCanMuteReads == reads)
    }

    @Test("whether the Mac can mute is read again as the warning opens; if it can't, the check mutes nothing")
    func checkMutingReadAsTheWarningOpens() async {
        let world = World()
        let model = await ready(world)
        world.antiDot = true
        let reads = world.macCanMuteReads
        world.macCanMute = false // another output chosen meanwhile
        model.continueToCheck() // the warning opens: read again, for it and the check
        #expect(model.checkMuting == .none && world.macCanMuteReads == reads + 1)
    }

    @Test("Use keeps the page's learned Play/Pause button when the page is the way chosen, and not with another way",
          arguments: [CheckResult.WayKind.page, .panel])
    func keepsThePageButton(_ way: CheckResult.WayKind) async {
        let button = PlayPauseRecipe(playLabel: "Play", pauseLabel: "Pause",
                                     places: [ButtonPlace(path: ["AXGroup", "AXToolbar"], distanceFromBottom: 51)])
        let found = CheckResult(
            ways: [CheckResult.WayResult(kind: .page, mark: .some, failedStates: [.hidden]), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.page(PageAccess(interface: .electron, switchAttribute: PageAccess.electronSwitch)), .panel(rememberedRow: nil)]),
            pageButton: button)
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.finished(found))
        await TestWait.until { model.result != nil }
        model.choose(way)
        model.use()
        #expect(world.used.first?.pageButton == (way == .page ? button : nil))
    }

    @Test("a stopped check can run again; a check that found no way says so")
    func stoppedAndNothing() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.stopCheck()
        await TestWait.until { model.stage == .stopped }
        #expect(world.run.stopped && model.state(of: .check) == .failed)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }

        let none = World()
        let empty = await ready(none)
        empty.startCheck()
        await TestWait.until { none.panel == ["shown"] }
        none.run.finish(.finished(CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .notThere)], setup: nil)))
        await TestWait.until { empty.result != nil }
        #expect(empty.state(of: .use) == .failed)
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

    @Test("Accessibility missing for the check while AutoHush still reads it allowed: nothing goes on by itself, Reopen AutoHush is offered; once AutoHush reads it missing, it's asked for as usual")
    func accessibilityNeedsReopen() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.run.finish(.permissionMissing) // the helper's answer; AutoHush's stays allowed
        await TestWait.until { model.stage == .allowing }
        #expect(model.accessibilityNeedsReopen && model.permissions.neededAllowed)
        model.continueWithoutAll()
        #expect(model.stage == .allowing)
        model.reopenForAccessibility()
        #expect(world.autoHushReopened == 1)

        world.permissions.accessibility = false // macOS told AutoHush after all
        await TestWait.until { !model.accessibilityNeedsReopen }
        world.permissions.accessibility = true // allowed again: on as usual
        await TestWait.until { model.stage != .allowing }
        model.reopenForAccessibility()
        #expect(world.autoHushReopened == 1)
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
        world.run.finish(.stopped) // else its task waits for good, keeping the model and the world
    }

    @Test("Stop while the last check still puts things back: the new one never starts, back to its step")
    func stopWhileLastCheckEnds() async {
        let world = World()
        let model = await ready(world)
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
    }

    @Test("Change… closes the warning before a check: its Start was for the app before")
    func changeClosesWarning() async {
        let world = World()
        let model = await ready(world)
        model.continueToCheck()
        let closed = world.warningsClosed
        model.changeApp()
        #expect(world.warningsClosed == closed + 1)
    }

    @Test("the app quitting while it's waited for says so; Open opens it (its step busy, the steps before still done) and waits again, or says so again when it doesn't open")
    func appQuits() async {
        let world = World()
        let model = await model(world)
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

    @Test("the app quitting and no longer found (moved or deleted) while it's waited for, or in the check, offers another app instead of Open or Check Again")
    func appGone() async {
        let world = World()
        let model = await model(world)
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
        let ready = await ready(checked)
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
        let model = await ready(world)
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
            let model = await ready(world)
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
        let model = await ready(world)
        model.startCheck()
        await TestWait.until { model.stage == .failed }
        #expect(model.failureReason == .other && world.panel.isEmpty && !model.canShowLog)
        world.hasLog = true
        model.showLog()
        #expect(model.canShowLog && world.logsShown == 1)
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
        let again = AddAppModel(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let model = await ready(world)
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
        let again = AddAppModel(world)
        again.reset()
        #expect(again.steps.contains(.reopen) && again.reopenOutcome == .skipped)
        again.use()
        #expect(world.asksToReopen == [false])
    }

    /// In AntiDot mode, Audio Recording turned down: the app playing, ready to check.
    private func readyInAntiDot() async -> (world: World, model: AddAppModel) {
        let world = World()
        world.antiDot = true
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        world.playing = true
        let model = await model(world)
        model.continueWithApp()
        await TestWait.until { model.stage == .ready } // all it uses is allowed
        return (world, model)
    }

    /// In AntiDot mode, a check run that found only a panel its sound tells
    /// (its row stale), Audio Recording allowed meanwhile.
    private func checkedInAntiDot() async -> (world: World, model: AddAppModel) {
        let (world, model) = await readyInAntiDot()
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        world.permissions.audio = .allowed
        world.run.finish(.finished(CheckResult(
            ways: [CheckResult.WayResult(kind: .menu, mark: .notThere), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.panel(rememberedRow: nil)], panelRowIsStale: true))))
        await TestWait.until { model.result != nil }
        return (world, model)
    }

    @Test("in AntiDot mode, Audio Recording isn't asked for or missed")
    func antiDot() async {
        let (_, model) = await readyInAntiDot()
        #expect(model.permissions.missingOptional(antiDot: true).isEmpty)
    }

    @Test("in AntiDot mode, the check taps nothing")
    func antiDotTapsNothing() async {
        let (world, model) = await readyInAntiDot()
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        #expect(world.taps == [false])
        world.run.finish(.stopped) // else its task waits for good, keeping the model and the world
    }

    @Test("in AntiDot mode, neither muting nor a panel only its sound tells can be used")
    func antiDotLeavesNoWay() async {
        let (world, model) = await checkedInAntiDot()
        #expect(!model.canMute && model.choosableWays.isEmpty && model.state(of: .use) == .failed && model.offersCheckAgain)
        model.use()
        #expect(world.used.isEmpty)
    }

    @Test("AntiDot mode turned off from Add an App lets a panel only its sound tells be used")
    func antiDotTurnedOff() async {
        let (world, model) = await checkedInAntiDot()
        model.turnOffAntiDot()
        #expect(!world.antiDot && model.choosableWays == [.panel] && model.state(of: .use) != .failed)
    }

    @Test("Audio Recording turned on in System Settings waits for AutoHush to reopen, which the window offers as soon as it's asked for")
    func audioAfterReopen() async {
        let world = World()
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        world.heldSleep = ManualSleep() // the permissions read again only after the request
        let model = await model(world)
        defer { model.windowClosed() } // its watch ends
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.audio == .denied }
        #expect(!model.audioAwaitsReopen)
        model.request(.audioRecording)
        await TestWait.until { model.audioAwaitsReopen }
        #expect(model.permissions.audio == .needsReopen)
        model.reopenAutoHush()
        #expect(world.autoHushReopened == 1)
    }
}
