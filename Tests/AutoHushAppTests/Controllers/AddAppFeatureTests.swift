import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AddAppFeature", .timeLimit(.minutes(1)))
@MainActor
struct AddAppFeatureTests {
    /// The host, the apps on the Mac and the check's helper (`World`), the
    /// app playing in AntiDot mode: nothing taps the app, so the Mac's
    /// output is muted instead.
    private let world = World()
    private let outputs = MockOutputMuting()
    private let suite = TestDefaults("AddAppFeatureTests")

    /// Whether the Mac's output is muted.
    private var muted: Bool { outputs.mutes[7] == true }

    /// Add an App on `world`, opened.
    private func opened() -> AddAppFeature {
        world.playing = true
        world.antiDot = true
        let sut = AddAppFeature(host: world, system: .init(outputMute: OutputMute(outputs: outputs, defaults: suite.defaults),
                                                           standIns: (reader: world, helper: world)),
                                keptChecks: world.kept)
        sut.open()
        return sut
    }

    /// Its app chosen, and a check started and running.
    private func checking(_ sut: AddAppFeature) async throws -> AddAppModel {
        let model = try #require(sut.model)
        await model.loadApps()
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        model.startCheck()
        await TestWait.until { world.runs == 1 }
        return model
    }

    @Test("opened, it makes its model on what it's given and shows its window")
    func opens() throws {
        defer { suite.remove() }
        let sut = opened()
        defer { sut.window?.close() }
        _ = try #require(sut.model)
        let window = try #require(sut.window)
        #expect(window.isOpen)
    }

    @Test("a check holds the player through its host while it runs")
    func checkThroughItsHost() async throws {
        defer { suite.remove() }
        let sut = opened()
        defer { sut.window?.close() }
        let model = try await checking(sut)
        #expect(world.holds == [true])
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }
        #expect(world.holds == [true, false])
    }

    @Test("a check mutes the Mac's output when the app can't be muted alone, and puts it back as it ends")
    func checkMutesTheMac() async throws {
        defer { suite.remove() }
        let sut = opened()
        defer { sut.window?.close() }
        let model = try await checking(sut)
        #expect(muted)
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }
        #expect(!muted)
    }

    @Test("the Mac's output muted for a check is put back as AutoHush quits")
    func quitPutsTheOutputBack() async throws {
        defer { suite.remove() }
        let sut = opened()
        defer { sut.window?.close() }
        let model = try await checking(sut)
        #expect(muted)
        sut.quit()
        #expect(!muted)
        world.run.finish(.stopped)
        await TestWait.until { model.stage == .stopped }
    }
}
