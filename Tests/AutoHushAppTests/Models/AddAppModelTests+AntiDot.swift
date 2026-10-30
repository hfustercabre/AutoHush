import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport
import CheckedPlayers
import WebAppPlayers

extension AddAppModelTests {
    /// In AntiDot mode, Audio Recording turned down: the app playing, ready to check.
    private func readyInAntiDot() async -> (world: World, model: AddAppModel) {
        let world = World()
        world.antiDot = true
        world.permissions = CheckPermissions(accessibility: true, audio: .denied)
        world.playing = true
        let model = await AddAppModel.opened(on: world)
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
        let model = await AddAppModel.opened(on: world)
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
