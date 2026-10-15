import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import CheckedPlayers

/// A check that ends when the test says.
@MainActor
private final class FakeCheckRun: CheckRunning {
    var stopped = false
    private var end: PlayerCheckEnd?
    private var waiting: CheckedContinuation<PlayerCheckEnd, Never>?

    func stop() {
        stopped = true
        finish(.stopped)
    }

    func finish(_ end: PlayerCheckEnd) {
        self.end = end
        waiting?.resume(returning: end)
        waiting = nil
    }

    func waitForEnd() async -> PlayerCheckEnd {
        if let end { return end }
        return await withCheckedContinuation { waiting = $0 }
    }
}

/// What the fake services saw and answer.
@MainActor
private final class World {
    var apps = [CheckableApp(bundleID: "com.example.player", name: "Player", url: URL(filePath: "/Applications/Player.app"), nowPlaying: true),
                CheckableApp(bundleID: "com.example.other", name: "Other", url: URL(filePath: "/Applications/Other.app"))]
    var traits = CheckedAppTraits(scriptable: false, framework: nil, needsLaunchOption: false)
    var running = true
    var runsWithOption: Bool?
    var permissions = CheckPermissions(accessibility: true, audio: .allowed)
    var playing = false
    var now = Date(timeIntervalSince1970: 1000)
    var opened: [(String, Bool)] = []
    var reopened = 0
    var warnings = 0
    var used: [CheckResult] = []
    var closed = 0
    var choosers = 0
    var panel: [String] = []
    let run = FakeCheckRun()

    var services: AddAppServices {
        AddAppServices(
            listApps: { self.apps },
            appAt: { url in
                url.lastPathComponent == "AutoHush.app" ? .failure(.autoHush)
                    : .success(CheckableApp(bundleID: "com.example.picked", name: "Picked", url: url))
            },
            showChooser: { self.choosers += 1 },
            traits: { _ in self.traits },
            isRunning: { _ in self.running },
            open: { app, option in
                self.opened.append((app.bundleID, option))
                self.running = true
                return true
            },
            runsWithLaunchOption: { _ in self.runsWithOption },
            reopen: { _ in
                self.reopened += 1
                return true
            },
            permissions: { _, scriptable in
                var permissions = self.permissions
                if scriptable, permissions.automation == nil { permissions.automation = .notAsked }
                return permissions
            },
            request: { _, _, _ in },
            isPlaying: { _, _ in self.playing },
            startCheck: { _, onLine in
                onLine("Press Test")
                return self.run
            },
            showWarning: { self.warnings += 1 },
            checkStarted: { _ in self.panel.append("shown") },
            checkEnded: { self.panel.append("hidden") },
            use: { self.used.append($0) },
            close: { self.closed += 1 },
            now: { self.now },
            sleep: { _ in await Task.yield() }
        )
    }
}

@MainActor
@Suite("AddAppModel", .timeLimit(.minutes(1)))
struct AddAppModelTests {
    private let result = CheckResult(
        ways: [CheckResult.WayResult(kind: .page, mark: .works), CheckResult.WayResult(kind: .menu, mark: .none)],
        setup: PlayerSetup(bundleID: "com.example.player", name: "Player", appURL: URL(filePath: "/Applications/Player.app"),
                           ways: [.panel(rememberedRow: nil)]))

    /// A model at its first step, its apps read.
    private func model(_ world: World) async -> AddAppModel {
        let model = AddAppModel(services: world.services)
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
        #expect(!model.permissions.neededAllowed && model.permissions.missingOptional == [.audioRecording])
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
        #expect(model.progress.stage == .testing && world.panel == ["shown"])
        world.run.finish(.finished(result))
        await TestWait.until { model.result != nil }
        #expect(world.panel == ["shown", "hidden"])
        #expect(model.mark(of: .check) == .done && model.mark(of: .use) == .current)
        model.use()
        #expect(world.used == [result] && world.closed == 1)
    }

    @Test("a stopped check can run again; a check that found no way says so")
    func stoppedAndNothing() async {
        let world = World()
        let model = await ready(world)
        model.startCheck()
        model.stopCheck()
        await TestWait.until { model.stage == .stopped }
        #expect(world.run.stopped && model.mark(of: .check) == .failed)
        model.checkAgain()
        await TestWait.until { model.stage == .ready }

        let none = World()
        let empty = await ready(none)
        empty.startCheck()
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
        model.windowClosed()
        #expect(world.run.stopped)
        await TestWait.until { world.panel == ["shown", "hidden"] }
    }
}
