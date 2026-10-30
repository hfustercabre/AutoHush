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
    let result = CheckResult(
        ways: [CheckResult.WayResult(kind: .menu, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
        setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                           ways: [.panel(rememberedRow: nil)]))

    @Test("the app playing in Now Playing is picked, or the only one there; the others that can play come after those in Now Playing")
    func choosing() async {
        let world = World()
        let model = await AddAppModel.opened(on: world)
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
        #expect(await AddAppModel.opened(on: paused).selectedID == "com.example.player")
        let none = World()
        none.apps[0].nowPlaying = nil
        #expect(await AddAppModel.opened(on: none).selectedID == nil)
    }

    @Test("choosing in the list, or an app picked on the disk, goes on; Change… starts over with the list")
    func chooser() async {
        let world = World()
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
        model.continueWithApp()
        #expect(model.stage == .opening && !model.canChangeApp)
        await TestWait.until { model.currentStep != .choose }
        #expect(world.opened.map(\.1) == [true])
        #expect(!model.needsReopen)

        let failing = World()
        failing.running = false
        failing.opens = false
        let unopened = await AddAppModel.opened(on: failing)
        unopened.continueWithApp()
        await TestWait.until { unopened.openFailed }
        #expect(unopened.stage == .choosing && failing.opened.count == 1 && unopened.canContinueWithApp)
    }

    @Test("permissions are watched until all are allowed; then it waits for the app to play, and it's ready once it plays")
    func permissionsThenPlaying() async {
        let world = World()
        world.permissions.accessibility = false
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
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
        let skipping = await AddAppModel.opened(on: other)
        skipping.continueWithApp()
        await TestWait.until { skipping.stage == .reopenAsked }
        skipping.skipReopen()
        #expect(skipping.reopenOutcome == .skipped && skipping.currentStep == .play && other.reopened == 0)
    }

    @Test("it gives up waiting for the app to play after 2 minutes, as the window says; Try Again waits again")
    func playTimeout() async {
        let world = World()
        let model = await AddAppModel.opened(on: world)
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
}
