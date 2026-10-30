import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import WebAppPlayers
import PlayerCheckKit

extension AddAppModelTests {
    @Test("Continue… shows the warning; its Start runs the check with its panel; what it found ends at Use")
    func checking() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
        #expect(model.checkMuting == .app)
    }

    @Test("the check mutes the Mac's output in AntiDot mode, as read with the permissions")
    func checkMutingInAntiDot() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        world.antiDot = true
        #expect(model.checkMuting == .mac) // as read with the permissions
    }

    @Test("whether the Mac can mute isn't read again each time what the check mutes is drawn")
    func checkMutingNotReadAtDrawing() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
        world.antiDot = true
        let reads = world.macCanMuteReads
        world.macCanMute = false // another output chosen meanwhile
        #expect(model.checkMuting == .mac && model.checkMuting == .mac) // drawn again: as read
        #expect(world.macCanMuteReads == reads)
    }

    @Test("whether the Mac can mute is read again as the warning opens; if it can't, the check mutes nothing")
    func checkMutingReadAsTheWarningOpens() async {
        let world = World()
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        model.stopCheck()
        await TestWait.until { model.stage == .stopped }
        #expect(world.run.stopped && model.state(of: .check) == .failed)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }

        let none = World()
        let empty = await AddAppModel.ready(on: none)
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
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
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
        let model = await AddAppModel.ready(on: world)
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
}
