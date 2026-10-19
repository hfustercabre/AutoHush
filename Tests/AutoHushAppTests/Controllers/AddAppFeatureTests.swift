import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AddAppFeature", .timeLimit(.minutes(1)))
@MainActor
struct AddAppFeatureTests {
    @Test("opened, it makes its model on what it's given and shows its window; a check holds the player through its host while it runs, and mutes the Mac's output when the app can't be muted alone; the output is put back as it ends, and as AutoHush quits")
    func checkThroughItsHost() async throws {
        let world = World() // the host, the apps on the Mac and the check's helper
        world.playing = true
        world.antiDot = true // nothing taps the app: the Mac's output is muted instead
        let outputs = MockOutputMuting()
        let suite = TestDefaults("AddAppFeatureTests")
        defer { suite.remove() }
        let sut = AddAppFeature(host: world, system: .init(outputMute: OutputMute(outputs: outputs, defaults: suite.defaults),
                                                           standIns: (reader: world, helper: world)),
                                keptChecks: world.kept)
        let muted = { outputs.mutes[7] == true }

        sut.open()
        let model = try #require(sut.model)
        let window = try #require(sut.window)
        defer { window.close() }
        #expect(window.isOpen)
        await model.loadApps()
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 1 }
        #expect(world.holds == [true] && muted())
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }
        #expect(world.holds == [true, false] && !muted())

        world.run = FakeCheckRun()
        model.checkAgain()
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 2 }
        #expect(muted())
        sut.quit()
        #expect(!muted())
        world.run.finish(.stopped)
        await TestWait.until { model.stage == .stopped }
    }
}
