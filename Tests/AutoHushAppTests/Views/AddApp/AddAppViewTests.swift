import AppKit
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import PlayerCheckKit

/// Add an App's window at its steps, drawn as the window draws it on
/// `World`'s stand-ins: no other test draws its Allow, Reopen and Use steps
/// (B4, the full check, 2026-10-27).
@Suite("Add an App's steps, drawn", .waitsTimeLimit)
@MainActor
struct AddAppViewTests {
    /// `NSApp` gives the window its icon: set up when this suite runs alone.
    init() {
        _ = NSApplication.shared
    }

    /// A model at its first step, its window open, its apps read.
    private func model(_ world: World) async -> AddAppModel {
        let model = AddAppModel(world)
        model.reset()
        await model.loadApps()
        return model
    }

    /// The window's content drawn at the model's step.
    private func draws(_ model: AddAppModel) -> Bool {
        drawn(AddAppView(model: model, close: {}), width: AddAppView.width, height: 1000).height > 0
    }

    @Test("the Allow step draws Accessibility missing, then the others missing with Continue; an app that can't be scripted with its note, one that can (in AntiDot mode, Audio Recording not needed) with Automation's row",
          arguments: [(false, false), (true, true)])
    func allowStep(_ antiDot: Bool, _ scriptable: Bool) async {
        let world = World()
        world.antiDot = antiDot
        world.traits.scriptable = scriptable
        world.permissions = CheckPermissions(accessibility: false, audio: .denied)
        let model = await model(world)
        defer { model.windowClosed() } // its watch ends
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.audio == .denied }
        #expect(!model.permissions.neededAllowed && draws(model))
        world.permissions.accessibility = true
        await TestWait.until { model.permissions.neededAllowed }
        #expect(model.stage == .allowing && !model.permissions.missingOptional(antiDot: antiDot).isEmpty) // waits for Continue
        #expect(draws(model))
    }

    @Test("the Allow step draws Audio Recording allowed in System Settings, waiting for AutoHush to reopen")
    func allowStepAwaitsReopen() async {
        let world = World()
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        world.heldSleep = ManualSleep() // the permissions read again only after the request
        let model = await model(world)
        defer { model.windowClosed() } // its watch ends
        model.continueWithApp()
        await TestWait.until { model.stage == .allowing && model.permissions.audio == .denied }
        model.request(.audioRecording)
        await TestWait.until { model.audioAwaitsReopen }
        #expect(draws(model))
    }

    @Test("the Reopen step draws asking, after a reopen that didn't go, and skipped, the app then waited for")
    func reopenStep() async {
        let world = World()
        world.traits.needsLaunchOption = true
        world.runsWithOption = false
        world.reopens = false // it didn't quit
        let model = await model(world)
        defer { model.windowClosed() }
        model.continueWithApp()
        await TestWait.until { model.stage == .reopenAsked }
        #expect(draws(model))
        model.reopen()
        await TestWait.until { model.reopenFailed }
        #expect(model.stage == .reopenAsked && draws(model))
        model.skipReopen()
        #expect(model.reopenOutcome == .skipped && model.currentStep == .play && draws(model))
    }

    @Test("the Use step draws the ways to choose, the recommended one that works only partly with its note in orange; or, none worked, Mute It Instead",
          arguments: [true, false])
    func useStep(_ worked: Bool) async {
        let found = CheckResult(
            ways: [CheckResult.WayResult(kind: .script, mark: .notThere), CheckResult.WayResult(kind: .menu, mark: .some, failedStates: [.hidden]),
                   CheckResult.WayResult(kind: .page, mark: .none), CheckResult.WayResult(kind: .panel, mark: .works)],
            setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                               ways: [.menu(menuName: "Playback"), .panel(rememberedRow: nil)]))
        let none = CheckResult(ways: [CheckResult.WayResult(kind: .page, mark: .none)], setup: nil)
        let world = World()
        world.playing = true
        let model = await model(world)
        defer { model.windowClosed() }
        model.continueWithApp()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.panel == ["shown"] }
        if !worked { world.permissions.audio = .denied } // nothing to use, and it can't be muted yet either
        world.run.finish(.finished(worked ? found : none))
        await TestWait.until { model.result != nil }
        if worked {
            #expect(model.choosableWays == [.menu, .panel]) // the menu recommended, though it works only partly
        } else {
            await TestWait.until { !model.canMute }
            #expect(model.choosableWays.isEmpty)
        }
        #expect(model.state(of: .use) == (worked ? .current : .failed) && draws(model))
    }
}
