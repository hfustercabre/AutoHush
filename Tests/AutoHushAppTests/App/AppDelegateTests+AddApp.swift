import AppKit
@testable import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

extension AppDelegateTests {
    // MARK: - Apps added with Add an App

    /// What Add an App's check found for an app it controls by its menu `menu`.
    private static func checked(_ id: String, _ name: String, menu: String) -> CheckResult {
        CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .works)],
                    setup: PlayerSetup(bundleID: id, name: name, appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
                                       ways: [.menu(menuName: menu)]))
    }

    /// First chosen, and two apps added with Add an App that need reopening:
    /// Kept, added before, and Added, checked now. AutoHush's alerts are
    /// answered by `answers` in turn (then Cancel), and noted by title, a
    /// removal of the chosen app marked so.
    @MainActor
    private func addedAppsBench(answers: [NSApplication.ModalResponse] = []) throws
        -> (scratch: Scratch, added: AddedApps, sut: AppDelegate, alerts: CallLog) {
        let scratch = Scratch()
        let added = AddedApps(scratch.addedSetups, needReopening: true)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { added.players() })
        scratch.installed.formUnion(["com.example.added", "com.example.kept"])
        scratch.addedSetups.save(try #require(Self.checked("com.example.kept", "Kept", menu: "Controls").setup)) // added before
        let (sut, _) = makeSUT(scratch)
        let alerts = CallLog()
        sut.runAlert = { alert in
            alerts.calls.append(alert.messageText + (alert.informativeText.hasPrefix("You’ll choose another player") ? " (chosen)" : ""))
            return alerts.calls.count <= answers.count ? answers[alerts.calls.count - 1] : .alertSecondButtonReturn
        }
        return (scratch, added, sut, alerts)
    }

    /// Added used right after Skip in its Reopen step: chosen, and not asked
    /// to reopen it, which the card says it needs.
    @MainActor
    private func useAdded(_ sut: AppDelegate) async {
        sut.useCheckedApp(Self.checked("com.example.added", "Added", menu: "Controls"), asksToReopen: false)
        await TestWait.until { sut.status.playerNeedsReopen }
    }

    @MainActor
    @Test("Add an App's Use keeps what the check found and chooses the app, not asking to reopen it when told not to")
    func addedAppUsed() async throws {
        let (scratch, _, sut, alerts) = try addedAppsBench()
        // Used right after Skip in its Reopen step: chosen, and not asked to reopen it.
        sut.useCheckedApp(Self.checked("com.example.added", "Added", menu: "Controls"), asksToReopen: false)
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.added", "com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Added", "Kept"])
        #expect(sut.player?.bundleID == "com.example.added")
        await TestWait.until { sut.status.playerNeedsReopen }
        #expect(alerts.calls.isEmpty)
    }

    /// Added used, then checked again while chosen and used again, its menu
    /// now Playback (Reopen Added?: Cancel): the player it was, and is now.
    @MainActor
    private func addedCheckedAgain() async throws
        -> (sut: AppDelegate, alerts: CallLog, used: MockMusicPlayer, usedAgain: MockMusicPlayer) {
        let (_, added, sut, alerts) = try addedAppsBench(answers: [.alertSecondButtonReturn]) // Reopen Added?: Cancel
        await useAdded(sut)
        let used = try #require(added.player("com.example.added"))
        sut.useCheckedApp(Self.checked("com.example.added", "Added", menu: "Playback"), asksToReopen: true)
        let usedAgain = try #require(added.player("com.example.added"))
        return (sut, alerts, used, usedAgain)
    }

    @MainActor
    @Test("an app added with Add an App, checked again while chosen and used, is chosen again with its new setup")
    func addedAppCheckedAgain() async throws {
        let (sut, _, used, usedAgain) = try await addedCheckedAgain()
        #expect(usedAgain !== used && sut.player.map { $0 as AnyObject } === usedAgain)
    }

    @MainActor
    @Test("an app added with Add an App, checked again while chosen and used, has the player it replaces let go of its app")
    func addedAppCheckedAgainLetsGo() async throws {
        let (sut, _, used, _) = try await addedCheckedAgain()
        await TestWait.until { await used.releases == 1 }
        withExtendedLifetime(sut) {}
    }

    @MainActor
    @Test("an app added with Add an App, checked again while chosen and used, asks whether to reopen it")
    func addedAppCheckedAgainAsksToReopen() async throws {
        let (sut, alerts, _, _) = try await addedCheckedAgain()
        await TestWait.until { alerts.calls.count == 1 }
        #expect(alerts.calls == ["Reopen Added?"])
        withExtendedLifetime(sut) {}
    }

    @MainActor
    @Test("Remove on an app added with Add an App asks first: Cancel keeps it, chosen")
    func addedAppRemoveCancelled() async throws {
        let (scratch, _, sut, alerts) = try addedAppsBench(answers: [.alertSecondButtonReturn]) // Remove Added?: Cancel
        await useAdded(sut)
        sut.removeAddedApp("com.example.added") // its row with Option held
        await TestWait.until { alerts.calls.count == 1 }
        #expect(sut.player?.bundleID == "com.example.added" && scratch.addedSetups.setups().count == 2)
        #expect(alerts.calls == ["Remove Added? (chosen)"])
    }

    /// Added used, its reopen choice and its check kept as Add an App keeps
    /// them, then removed while it's chosen (Remove Added?: Remove).
    @MainActor
    private func addedRemovedWhileChosen() async throws
        -> (scratch: Scratch, sut: AppDelegate, alerts: CallLog, used: MockMusicPlayer, kept: KeptCheckStore) {
        let (scratch, added, sut, alerts) = try addedAppsBench(answers: [.alertFirstButtonReturn]) // Remove Added?: Remove
        await useAdded(sut)
        let used = try #require(added.player("com.example.added"))
        // Removed while it's chosen, as Add an App kept its check.
        ReopenChoices.setReopensAlways("com.example.added", defaults: scratch.defaults)
        let kept = KeptCheckStore(defaults: scratch.defaults)
        kept.save(KeptCheck(app: CheckableApp(bundleID: "com.example.added", name: "Added", url: URL(fileURLWithPath: "/Applications/com.example.added.app")),
                            result: Self.checked("com.example.added", "Added", menu: "Controls"), at: Date()))
        sut.removeAddedApp("com.example.added")
        await TestWait.until { alerts.calls.count == 1 }
        return (scratch, sut, alerts, used, kept)
    }

    @MainActor
    @Test("Remove, once asked, forgets the setup of an app added with Add an App, which leaves the list")
    func addedAppRemoved() async throws {
        let (scratch, sut, alerts, _, _) = try await addedRemovedWhileChosen()
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Kept"])
        #expect(alerts.calls == ["Remove Added? (chosen)"])
    }

    @MainActor
    @Test("Remove forgets the reopen choice of an app added with Add an App")
    func addedAppRemovedForgetsReopen() async throws {
        let (scratch, _, _, _, _) = try await addedRemovedWhileChosen()
        #expect(!ReopenChoices.reopensAlways("com.example.added", defaults: scratch.defaults))
    }

    @MainActor
    @Test("Remove forgets the check Add an App kept of the app it added")
    func addedAppRemovedForgetsCheck() async throws {
        let (_, _, _, _, kept) = try await addedRemovedWhileChosen()
        #expect(kept.load() == nil)
    }

    @MainActor
    @Test("Remove on the app added with Add an App that's chosen lets go of its app")
    func addedAppRemovedLetsGo() async throws {
        let (_, sut, _, used, _) = try await addedRemovedWhileChosen()
        await TestWait.until { await used.releases == 1 } // its mute or switch back off
        withExtendedLifetime(sut) {}
    }

    @MainActor
    @Test("Remove on the app added with Add an App that's chosen leaves none chosen, and the welcome window asks for one")
    func addedAppRemovedChoosesNone() async throws {
        let (scratch, sut, _, _, _) = try await addedRemovedWhileChosen()
        #expect(sut.player == nil && scratch.preferences.musicPlayer == nil)
        #expect(scratch.chooser.isOpen)
    }

    @MainActor
    @Test("an app added with Add an App that isn't chosen just leaves the list once removed")
    func addedAppNotChosenRemoved() async throws {
        let (scratch, added, sut, alerts) = try addedAppsBench(answers: [.alertFirstButtonReturn]) // Remove Kept?: Remove
        sut.removeAddedApp("com.example.kept")
        await TestWait.until { alerts.calls.count == 1 }
        #expect(scratch.addedSetups.setups().isEmpty)
        #expect(!sut.status.playerOptions.contains { $0.kind == .checkedApp })
        #expect(alerts.calls == ["Remove Kept?"])
        let keptPlayer = try #require(added.player("com.example.kept"))
        #expect(await keptPlayer.releases == 0) // not chosen: nothing to let go of
    }

    /// Add an App opened on the stand-ins (its windows are AutoHush's own),
    /// an app playing to check, and the apps read at its first step.
    @MainActor
    @Test("Add an App, which asked AutoHush to reopen, opens again at launch with its app chosen; a note from long before doesn't")
    func addAppAfterRelaunch() async throws {
        let scratch = Scratch()
        let world = World()
        world.playing = true
        scratch.defaults.set(["at": scratch.clock.now, "app": world.apps[0].url.path], forKey: AppDelegate.addAppAfterRelaunchKey)
        let (sut, _) = makeSUT(scratch, addApp: world)
        sut.reopenAddAppIfAsked()
        let model = try #require(sut.addApp.model)
        #expect(sut.addApp.window?.isOpen == true)
        await TestWait.until { model.chosen?.bundleID == "com.example.picked" } // as the stand-in reads the app at that path
        #expect(scratch.defaults.dictionary(forKey: AppDelegate.addAppAfterRelaunchKey) == nil)
        sut.addApp.window?.close()

        let stale = Scratch()
        stale.defaults.set(["at": stale.clock.now.addingTimeInterval(-600), "app": ""], forKey: AppDelegate.addAppAfterRelaunchKey)
        let (late, _) = makeSUT(stale, addApp: World())
        late.reopenAddAppIfAsked()
        #expect(late.addApp.model == nil && stale.defaults.dictionary(forKey: AppDelegate.addAppAfterRelaunchKey) == nil)
    }

    @MainActor
    private func addAppOpened() async throws -> (scratch: Scratch, world: World, sut: AppDelegate, feature: AddAppFeature) {
        let scratch = Scratch()
        let world = World()
        world.playing = true
        let (sut, _) = makeSUT(scratch, addApp: world)
        let feature = try #require(sut.addApp)
        sut.openAddApp()
        let model = try #require(feature.model)
        await TestWait.until { !model.apps.isEmpty } // read at its first step
        return (scratch, world, sut, feature)
    }

    @MainActor
    @Test("Add an App opens at its first step, or as it is while it's open, with the same model and window")
    func addAppOpensAsItIs() async throws {
        let (_, world, sut, feature) = try await addAppOpened()
        let window = try #require(feature.window)
        let model = try #require(feature.model)
        defer { window.close() }
        #expect(window.isOpen)
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        sut.openAddApp() // open: shown as it is
        #expect(model.stage == .ready && feature.window === window && feature.model === model)
    }

    @MainActor
    @Test("Add an App's list of apps opens in a window of its own")
    func addAppChooserWindow() async throws {
        let (_, _, _, feature) = try await addAppOpened()
        let model = try #require(feature.model)
        defer { feature.window?.close() } // its list too
        model.openChooser()
        let chooser = try #require(feature.chooserWindow)
        #expect(chooser.isOpen)
    }

    @MainActor
    @Test("the warning's Start starts Add an App's check; closed while it runs, Add an App opens again at its first step, in the same window")
    func checkWarningStarts() async throws {
        let (_, world, sut, feature) = try await addAppOpened()
        let window = try #require(feature.window)
        let model = try #require(feature.model)
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        model.continueToCheck()
        let warning = try #require(feature.warningWindow)
        let warningView = try #require(warning.window?.contentViewController as? NSHostingController<CheckWarningView>)
        warningView.rootView.start()
        await TestWait.until { world.runs == 1 }
        #expect(model.stage == .checking && !warning.isOpen)

        // Closed (the check stops), then opened again: from its first step.
        window.close()
        await TestWait.until { !window.isOpen }
        sut.openAddApp()
        #expect(feature.window === window && window.isOpen && model.stage == .choosing && model.chosen == nil)
        window.close()
    }

    /// Add an App opened on the stand-ins, its app ready to check, in
    /// AntiDot mode or not: AutoHush's own start and end of a check, around
    /// the stand-in check.
    @MainActor
    private func readyToCheck(antiDot: Bool) async throws -> CheckBench {
        let scratch = Scratch()
        let world = World()
        world.playing = true
        let (sut, _) = makeSUT(scratch, addApp: world)
        if antiDot { sut.settingsModel.useAntiDotMode() }
        sut.openAddApp()
        let model = try #require(sut.addApp.model)
        await model.loadApps()
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        return CheckBench(scratch: scratch, world: world, sut: sut, model: model)
    }

    @MainActor
    @Test("the warning before Add an App's check doesn't open while no app is chosen")
    func checkWarningNeedsAnApp() async throws {
        let (_, _, _, feature) = try await addAppOpened()
        defer { feature.window?.close() }
        feature.showWarning() // no app chosen yet: no warning
        #expect(feature.warningWindow == nil)
    }

    /// The warning before the check of `bench`'s app, as its Continue… opens it.
    @MainActor
    private func warningShown(_ bench: CheckBench) throws -> (window: CheckWarningWindowController, view: CheckWarningView) {
        bench.model.continueToCheck()
        let warning = try #require(bench.sut.addApp.warningWindow)
        let view = try #require(warning.window?.contentViewController as? NSHostingController<CheckWarningView>)
        return (warning, view.rootView)
    }

    @MainActor
    @Test("the warning before Add an App's check opens in a window of its own once an app is chosen")
    func checkWarningWindow() async throws {
        let bench = try await readyToCheck(antiDot: false)
        defer { bench.sut.addApp.window?.close() } // its warning too
        let (warning, _) = try warningShown(bench)
        #expect(warning.isOpen)
    }

    @MainActor
    @Test("a new warning before Add an App's check replaces the last")
    func checkWarningReplaced() async throws {
        let bench = try await readyToCheck(antiDot: false)
        defer { bench.sut.addApp.window?.close() } // its warning too
        let (warning, _) = try warningShown(bench)
        let (next, _) = try warningShown(bench)
        await TestWait.until { !warning.isOpen }
        #expect(next !== warning && next.isOpen)
    }

    @MainActor
    @Test("the warning before Add an App's check mutes the app, with Audio Recording allowed outside AntiDot mode")
    func checkWarningMutesTheApp() async throws {
        let bench = try await readyToCheck(antiDot: false)
        defer { bench.sut.addApp.window?.close() } // its warning too
        let (_, view) = try warningShown(bench)
        #expect(view.muting == .app)
    }

    @MainActor
    @Test("the warning before Add an App's check mutes the Mac's sound in AntiDot mode")
    func checkWarningMutesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() } // its warning too
        let (_, view) = try warningShown(bench)
        #expect(view.muting == .mac)
    }

    @MainActor
    @Test("the warning before Add an App's check mutes nothing in AntiDot mode when the Mac's output can't be muted")
    func checkWarningMutesNothing() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() } // its warning too
        bench.scratch.outputs.mutes = [:] // its output has no mute control
        let (_, view) = try warningShown(bench)
        #expect(view.muting == .none)
    }

    @MainActor
    @Test("a check that taps the app's own sound never mutes the Mac's output")
    func checkTappingLeavesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: false)
        defer { bench.sut.addApp.window?.close() }
        #expect(bench.model.checkMuting == .app) // its own sound tapped: the Mac's is left alone
        await bench.check()
        #expect(!bench.muted)
        bench.world.run.finish(.failed(1))
        await TestWait.until { bench.model.stage == .failed }
    }

    @MainActor
    @Test("a check that can't mute only its app (AntiDot mode) mutes the Mac's output while it runs, and puts it back as it ends")
    func checkMutesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() }
        #expect(bench.model.checkMuting == .mac)
        await bench.check()
        #expect(bench.muted)
        bench.world.run.finish(.failed(1)) // it ends
        await TestWait.until { bench.model.stage == .failed }
        #expect(!bench.muted)
    }

    @MainActor
    @Test("the Mac's output, muted for a check, is put back as the check stops")
    func checkStoppedUnmutesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() }
        await bench.check()
        #expect(bench.muted)
        bench.model.stopCheck()
        await TestWait.until { bench.model.stage == .stopped }
        #expect(!bench.muted)
    }

    @MainActor
    @Test("the Mac's output, muted for a check, is put back as AutoHush quits")
    func quitUnmutesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() }
        await bench.check()
        bench.sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!bench.muted)
        bench.world.run.finish(.stopped)
        await TestWait.until { bench.model.stage == .stopped }
    }

    @MainActor
    @Test("the Mac's output, muted for a check AutoHush crashed during, is put back at the next launch")
    func nextLaunchUnmutesTheMac() async throws {
        let bench = try await readyToCheck(antiDot: true)
        defer { bench.sut.addApp.window?.close() }
        await bench.check()
        #expect(bench.muted)
        let (next, _) = makeSUT(bench.scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(!bench.muted)
        bench.world.run.finish(.stopped)
        await TestWait.until { bench.model.stage == .stopped }
    }

    @MainActor
    @Test("the Mac's volume lowered for the music (Level the volume) is put back as AutoHush quits, and at the next launch after a crash")
    func loweredVolumePutBack() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.volumeLeveler.lower(by: -6)
        #expect(scratch.volume.decibels == [0: -16])
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(scratch.volume.decibels == [0: -10])

        sut.volumeLeveler.lower(by: -6)
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(scratch.volume.decibels == [0: -10])
    }

    /// Now Playing shown in the menu bar for a press while the user hid it,
    /// through the setting AutoHush is given, as AutoHush leaves it then.
    @MainActor
    private static func nowPlayingShownForAPress(_ scratch: Scratch) {
        scratch.nowPlaying.value = 16 // shown while active, for the press
        scratch.defaults.set(["value": 24, "pid": Int(getpid())], forKey: NowPlayingSetting.leftKey)
    }

    @MainActor
    @Test("Now Playing, shown in the menu bar for a press while the user hid it, is hidden again as AutoHush quits")
    func nowPlayingPutBack() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        Self.nowPlayingShownForAPress(scratch)
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(scratch.nowPlaying.value == 24 && scratch.defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
    }

    @MainActor
    @Test("Now Playing, shown in the menu bar for a press while the user hid it, is hidden again at the next launch after a crash")
    func nowPlayingPutBackAfterCrash() {
        let scratch = Scratch()
        Self.nowPlayingShownForAPress(scratch)
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(scratch.nowPlaying.value == 24 && scratch.defaults.object(forKey: NowPlayingSetting.leftKey) == nil)
    }
}

/// The apps added with Add an App, as the catalog finds them: a stand-in for
/// each setup kept (one that lets go of what it turned on in its app as it
/// goes back off), made again when its setup changes (checked again), as
/// `CheckedPlayers` makes them.
private final class AddedApps: Sendable {
    private let setups: MemorySetupStore
    private let needReopening: Bool
    private let made = Locked<[String: (setup: PlayerSetup, player: MockMusicPlayer)]>([:])

    init(_ setups: MemorySetupStore, needReopening: Bool = false) {
        self.setups = setups
        self.needReopening = needReopening
    }

    func players() -> [any MusicPlayer] {
        let kept = setups.setups()
        return made.withLock { made in
            kept.map { setup in
                if let known = made[setup.bundleID], known.setup == setup { return known.player }
                let player = MockMusicPlayer(bundleID: setup.bundleID, name: setup.name, canFade: false, kind: .checkedApp,
                                             releasesOnQuit: true, needsReopening: needReopening)
                made[setup.bundleID] = (setup, player)
                return player
            }
        }
    }

    /// The one made last for `bundleID`.
    func player(_ bundleID: String) -> MockMusicPlayer? { made.value[bundleID]?.player }
}

/// Add an App's check on the stand-ins, its app ready to check
/// (`AppDelegateTests.readyToCheck`).
@MainActor
private struct CheckBench {
    let scratch: AppDelegateTests.Scratch
    let world: World
    let sut: AppDelegate
    let model: AddAppModel

    /// Whether the Mac's output is muted.
    var muted: Bool { scratch.outputs.mutes[7] == true }

    /// Starts a check and waits until it runs.
    func check() async {
        world.run = FakeCheckRun()
        let runs = world.runs
        model.startCheck()
        await TestWait.until { world.runs == runs + 1 }
    }
}
