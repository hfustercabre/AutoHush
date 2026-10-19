import AppKit
import CheckedPlayers
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

    @MainActor
    @Test("Add an App's Use keeps what the check found and chooses the app, again once checked again (its new setup used, asking to reopen it as told); Remove asks first: Cancel keeps it; Remove forgets it, and the chosen app lets go of its app, none is chosen and the welcome window asks; one not chosen just leaves the list")
    func addedAppUsedAndRemoved() async throws {
        let scratch = Scratch()
        let added = AddedApps(scratch.addedSetups, needReopening: true)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { added.players() })
        scratch.installed.formUnion(["com.example.added", "com.example.kept"])
        func result(_ id: String, _ name: String, menu: String) -> CheckResult {
            CheckResult(ways: [CheckResult.WayResult(kind: .menu, mark: .works)],
                        setup: PlayerSetup(bundleID: id, name: name, appURL: URL(fileURLWithPath: "/Applications/\(id).app"),
                                           ways: [.menu(menuName: menu)]))
        }
        scratch.addedSetups.save(try #require(result("com.example.kept", "Kept", menu: "Controls").setup)) // added before
        let (sut, _) = makeSUT(scratch)
        let alerts = CallLog()
        // Reopen Added?: Cancel. Remove Added?: Cancel, then Remove. Remove Kept?: Remove.
        let answers: [NSApplication.ModalResponse] = [.alertSecondButtonReturn, .alertSecondButtonReturn,
                                                      .alertFirstButtonReturn, .alertFirstButtonReturn]
        sut.runAlert = { alert in
            alerts.calls.append(alert.messageText + (alert.informativeText.hasPrefix("It’s your current player") ? " (chosen)" : ""))
            return alerts.calls.count <= answers.count ? answers[alerts.calls.count - 1] : .alertSecondButtonReturn
        }

        // Used right after Skip in its Reopen step: chosen, and not asked to reopen it.
        sut.useCheckedApp(result("com.example.added", "Added", menu: "Controls"), asksToReopen: false)
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.added", "com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Added", "Kept"])
        #expect(sut.player?.bundleID == "com.example.added")
        await TestWait.until { sut.status.playerNeedsReopen }
        let used = try #require(added.player("com.example.added"))

        // Checked again while chosen: chosen again with its new setup, the
        // player it replaces lets go of its app, and reopening is asked.
        sut.useCheckedApp(result("com.example.added", "Added", menu: "Playback"), asksToReopen: true)
        let usedAgain = try #require(added.player("com.example.added"))
        #expect(usedAgain !== used && sut.player.map { $0 as AnyObject } === usedAgain)
        await TestWait.until { alerts.calls.count == 1 }
        await TestWait.until { await used.releases == 1 }
        #expect(await used.releases == 1)

        // Remove Added… (its row with Option held), while it's chosen, as Add an App kept its check.
        ReopenChoices.setReopensAlways("com.example.added", defaults: scratch.defaults)
        let kept = KeptCheckStore(defaults: scratch.defaults)
        kept.save(KeptCheck(app: CheckableApp(bundleID: "com.example.added", name: "Added", url: URL(fileURLWithPath: "/Applications/com.example.added.app")),
                            result: result("com.example.added", "Added", menu: "Playback"), at: Date()))
        sut.removeAddedApp("com.example.added")
        await TestWait.until { alerts.calls.count == 2 }
        #expect(sut.player?.bundleID == "com.example.added" && scratch.addedSetups.setups().count == 2) // Cancel

        sut.removeAddedApp("com.example.added")
        await TestWait.until { alerts.calls.count == 3 }
        #expect(sut.player == nil && scratch.preferences.musicPlayer == nil)
        #expect(scratch.chooser.isOpen) // none is chosen: the welcome window asks
        #expect(scratch.addedSetups.setups().map(\.bundleID) == ["com.example.kept"])
        #expect(sut.status.playerOptions.filter { $0.kind == .checkedApp }.map(\.name) == ["Kept"])
        #expect(!ReopenChoices.reopensAlways("com.example.added", defaults: scratch.defaults))
        #expect(kept.load() == nil)
        await TestWait.until { await usedAgain.releases == 1 }
        #expect(await usedAgain.releases == 1) // its mute or switch back off

        sut.removeAddedApp("com.example.kept")
        await TestWait.until { alerts.calls.count == 4 }
        #expect(scratch.addedSetups.setups().isEmpty)
        #expect(!sut.status.playerOptions.contains { $0.kind == .checkedApp })
        #expect(alerts.calls == ["Reopen Added?", "Remove Added? (chosen)", "Remove Added? (chosen)", "Remove Kept?"])
        let keptPlayer = try #require(added.player("com.example.kept"))
        #expect(await keptPlayer.releases == 0) // not chosen: nothing to let go of
    }

    @MainActor
    @Test("Add an App opens at its first step, or as it is while it's open, with the same model and window; its list of apps and the warning before the check open in windows of their own, a new warning replacing the last, which mutes the app only with Audio Recording allowed outside AntiDot mode, else the Mac's sound, if its output can be muted; its Start starts the check")
    func addAppWindows() async throws {
        let (sut, _) = makeSUT()
        let world = World()
        world.playing = true
        var services = world.services
        // As AutoHush's own services hand these over.
        services.showChooser = { [weak sut] in sut?.showAppChooser() }
        services.showWarning = { [weak sut] in sut?.showCheckWarning() }
        let model = AddAppModel(services: services)
        sut.addAppModel = model

        sut.showAddApp()
        let window = try #require(sut.addAppWindow)
        #expect(window.isOpen && sut.addAppModel === model)
        await TestWait.until { !model.apps.isEmpty } // read at its first step
        sut.showCheckWarning() // no app chosen yet: no warning
        #expect(sut.checkWarningWindow == nil)

        model.openChooser()
        let chooser = try #require(sut.appChooserWindow)
        #expect(chooser.isOpen)
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        sut.showAddApp() // open: shown as it is
        #expect(model.stage == .ready && sut.addAppWindow === window)

        model.continueToCheck()
        let warning = try #require(sut.checkWarningWindow)
        let warningView = try #require(warning.window?.contentViewController as? NSHostingController<CheckWarningView>)
        #expect(warning.isOpen && warningView.rootView.muting == .app)
        world.antiDot = true
        model.continueToCheck()
        let macMuted = try #require(sut.checkWarningWindow)
        let macMutedView = try #require(macMuted.window?.contentViewController as? NSHostingController<CheckWarningView>)
        await TestWait.until { !warning.isOpen }
        #expect(macMuted !== warning && macMuted.isOpen && macMutedView.rootView.muting == .mac)
        world.macCanMute = false
        model.continueToCheck()
        let unmuted = try #require(sut.checkWarningWindow)
        let unmutedView = try #require(unmuted.window?.contentViewController as? NSHostingController<CheckWarningView>)
        await TestWait.until { !macMuted.isOpen }
        #expect(unmuted.isOpen && unmutedView.rootView.muting == .none)

        unmutedView.rootView.start()
        await TestWait.until { world.runs == 1 }
        #expect(model.stage == .checking && !unmuted.isOpen)

        // Closed (the check stops), then opened again: from its first step.
        window.close()
        chooser.close()
        await TestWait.until { !window.isOpen }
        sut.showAddApp()
        #expect(sut.addAppWindow === window && window.isOpen && model.stage == .choosing && model.chosen == nil)
        window.close()
    }

    @MainActor
    @Test("a check that can't mute only its app (AntiDot mode, or no Audio Recording) mutes the Mac's output while it runs, never one that taps the app's own sound; the output is put back as the check ends, as it stops, as AutoHush quits, and at the next launch after a crash during one")
    func checkMutesTheMac() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let world = World()
        world.playing = true
        // AutoHush's own start and end of a check, around the stand-in check.
        let live = sut.liveAddAppServices()
        var services = world.services
        services.macCanMute = live.macCanMute
        services.checkStarted = live.checkStarted
        services.checkEnded = live.checkEnded
        let model = AddAppModel(services: services)
        sut.addAppModel = model
        model.reset()
        await model.loadApps()
        model.choose(world.apps[0])
        await TestWait.until { model.stage == .ready }
        func check() async {
            world.run = FakeCheckRun()
            let runs = world.runs
            model.startCheck()
            await TestWait.until { world.runs == runs + 1 }
        }
        func checkAgain() async {
            model.checkAgain()
            await TestWait.until { model.stage == .ready }
        }
        let muted = { scratch.outputs.mutes[7] == true }

        #expect(model.checkMuting == .app) // its own sound tapped: the Mac's is left alone
        await check()
        #expect(!muted())
        world.run.finish(.failed(1))
        await TestWait.until { model.stage == .failed }

        world.antiDot = true
        #expect(model.checkMuting == .mac)
        await checkAgain()
        await check()
        #expect(muted())
        world.run.finish(.failed(1)) // it ends
        await TestWait.until { model.stage == .failed }
        #expect(!muted())

        await checkAgain()
        await check()
        #expect(muted())
        model.stopCheck()
        await TestWait.until { model.stage == .stopped }
        #expect(!muted())

        await checkAgain()
        await check()
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(!muted())
        world.run.finish(.stopped)
        await TestWait.until { model.stage == .stopped }

        await checkAgain()
        await check()
        #expect(muted())
        let (next, _) = makeSUT(scratch) // AutoHush crashed: the next launch
        next.putBackWhatWasLeft()
        #expect(!muted())
        world.run.finish(.stopped)
        await TestWait.until { model.stage == .stopped }
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

    @MainActor
    @Test("Now Playing, shown in the menu bar for a press while the user hid it, is hidden again as AutoHush quits, and at the next launch after a crash, through the setting AutoHush is given")
    func nowPlayingPutBack() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        func shownForAPress() {
            scratch.nowPlaying.value = 16 // shown while active, for the press
            scratch.defaults.set(["value": 24, "pid": Int(getpid())], forKey: NowPlayingSetting.leftKey)
        }
        shownForAPress()
        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(scratch.nowPlaying.value == 24 && scratch.defaults.object(forKey: NowPlayingSetting.leftKey) == nil)

        shownForAPress()
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
