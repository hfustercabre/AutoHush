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
    // MARK: - Players that learn

    @MainActor
    @Test("another app's launch, or one without a bundle identifier, doesn't change the health or start again",
          arguments: ["org.videolan.vlc", nil] as [String?])
    func otherAppLaunchDoesNothing(bundleID: String?) async {
        let (sut, monitorings) = makeSUT()
        await start(sut)

        sut.handleApplicationDidLaunch(bundleIdentifier: bundleID)
        await sut.session.waitUntilIdle()
        #expect(sut.status.health == .ready)
        #expect(monitorings.made.count == 1)
    }

    @MainActor
    @Test("the chosen player's launch sets app back to starting and starts it again")
    func playerLaunchSetsStartingState() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await TestWait.until { sut.status.health == .degraded("First isn’t running") }

        await scratch.first.setFailVerify(nil)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        #expect(sut.status.health == .starting)
        await TestWait.until { sut.status.health == .ready }
        #expect(monitorings.made.count == 2) // the one listing the apps while it was closed, then its own
        #expect(monitorings.made[0].isStopped && !monitorings.made[1].isStopped)
    }

    @MainActor
    @Test("an app that plays only the volume sound (BetterDisplay) is ignored once it runs; others aren't")
    func volumeSoundAppsIgnored() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let betterDisplay = AudioSource(id: "pro.betterdisplay.BetterDisplay", name: "BetterDisplay")
        sut.ignoreVolumeSoundApps([betterDisplay, AudioSource(id: "org.videolan.vlc", name: "VLC")])
        #expect(sut.userSettings.state.ignoredApps.map(\.id) == [betterDisplay.id])
        #expect(sut.status.ignoredApps.map(\.id) == [betterDisplay.id]) // in the menu's Ignored Apps
        #expect(monitorings.made[0].ignored == [betterDisplay.id]) // the monitoring ignores it
    }

    @MainActor
    @Test("macOS's notices reach AutoHush: the chosen player opening starts it again, an app that plays only the volume sound opening is ignored, the Mac sleeping and waking (or only its screens) reach the session; once AutoHush quits, a launch does nothing")
    func workspaceNotices() async throws {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await TestWait.until { sut.status.health == .degraded("First isn’t running") }
        sut.registerPlayerLaunchObserver()
        let observer = sut.playerLaunchObserver
        sut.registerPlayerLaunchObserver() // once only
        #expect(observer != nil && sut.playerLaunchObserver === observer)
        sut.registerSleepObservers()
        let center = NSWorkspace.shared.notificationCenter
        func launch(_ app: FakeRunningApplication) {
            center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                        userInfo: [NSWorkspace.applicationUserInfoKey: app])
        }

        await scratch.first.setFailVerify(nil)
        launch(FakeRunningApplication(bundleID: Players.first))
        await TestWait.until { sut.status.health == .ready }
        #expect(monitorings.made.count == 2) // the one listing the apps while it was closed, then its own

        // BetterDisplay opened (an app on the disk: a running app's bundle names it).
        let folder = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let betterDisplay = try TestAppBundle.make(in: folder, name: "BetterDisplay", info: ["CFBundleIdentifier": "pro.betterdisplay.BetterDisplay"])
        launch(FakeRunningApplication(bundleID: "pro.betterdisplay.BetterDisplay", bundleURL: betterDisplay))
        await TestWait.until { !sut.userSettings.state.ignoredApps.isEmpty }
        #expect(sut.userSettings.state.ignoredApps.map(\.id) == ["pro.betterdisplay.BetterDisplay"])

        for (notice, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                 (NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            center.post(name: notice, object: nil)
            await TestWait.until { sut.session.isAsleep == asleep }
        }
        #expect(monitorings.made.last?.asleep == [true, false, true, false])

        sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        #expect(sut.playerLaunchObserver == nil && sut.sleepObservers.isEmpty)
        launch(FakeRunningApplication(bundleID: Players.first))
        await Task.yield() // what a notice still observed would start
        await sut.session.waitUntilIdle()
        #expect(monitorings.made.count == 2) // not started again
    }

    // MARK: - A player opened without what it needs

    @MainActor
    @Test("a player opened without the option it needs: one to reopen always is reopened at once, but found so again within a minute only the card says so; its Reopen reopens it; any other is left to the card, or, just chosen, asked about: Cancel leaves it so, Reopen with the box ticked reopens it from then on")
    func playerNeedingReopen() async {
        let scratch = Scratch()
        let tunes = MockMusicPlayer(bundleID: "com.example.tunes", name: "Tunes")
        let radio = MockMusicPlayer(bundleID: "com.example.radio", name: "Radio")
        await tunes.setNeedsReopening(true, afterReopen: true) // a launcher that drops the option
        await radio.setNeedsReopening(true)
        scratch.players = MusicPlayerCatalog(players: [tunes, radio])
        scratch.installed = [tunes.bundleID, radio.bundleID]
        // The alert's box ticked for Tunes.
        ReopenChoices.setReopensAlways(tunes.bundleID, defaults: scratch.defaults)

        // Reopened at once; found so again right after, it isn't quit and
        // reopened over and over.
        let (sut, _) = makeSUT(scratch, chosenPlayer: tunes.bundleID)
        await TestWait.until { sut.status.playerNeedsReopen }
        #expect(await tunes.reopenCount == 1)
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        await TestWait.until { sut.lastReopens[tunes.bundleID]?.gaveUp == true } // given up this time
        #expect(await tunes.reopenCount == 1)
        #expect(sut.status.playerNeedsReopen)
        // Found so again over a minute later, it's reopened by itself again.
        scratch.clock.advance(by: 61)
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        await TestWait.until { await tunes.reopenCount == 2 }
        #expect(await tunes.reopenCount == 2)

        await tunes.setNeedsReopening(true)
        sut.reopenChosenPlayer() // the card's Reopen
        await TestWait.until { !sut.status.playerNeedsReopen }
        #expect(!sut.status.playerNeedsReopen)
        #expect(await tunes.reopenCount == 3)

        sut.chooseMusicPlayer(radio.bundleID, asksToReopen: false) // not asked: reopening it was just skipped in Add an App
        await TestWait.until { sut.status.playerNeedsReopen }
        #expect(await radio.reopenCount == 0)

        // Asked when one is chosen: Reopen (Return) or Cancel (Escape), and the box.
        let alert = AppDelegate.reopenAlert("Radio")
        #expect(alert.messageText == "Reopen Radio?")
        #expect(alert.buttons.map(\.title) == ["Reopen Radio", "Cancel"])
        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        #expect(alert.showsSuppressionButton && alert.suppressionButton?.title == "Always reopen Radio this way")

        // Cancel leaves it to the card, the box ticked or not; Reopen with the
        // box ticked reopens it, and from then on without asking.
        let shown = CallLog()
        sut.runAlert = { alert in
            shown.calls.append(alert.messageText)
            alert.suppressionButton?.state = .on
            return shown.calls.count == 1 ? .alertSecondButtonReturn : .alertFirstButtonReturn
        }
        sut.chooseMusicPlayer(radio.bundleID, replacing: true) // checked again in Add an App, and used
        await TestWait.until { shown.calls.count == 1 }
        #expect(await radio.reopenCount == 0)
        #expect(sut.status.playerNeedsReopen)
        #expect(!ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))

        sut.chooseMusicPlayer(radio.bundleID, replacing: true)
        await TestWait.until { await radio.reopenCount == 1 }
        await TestWait.until { !sut.status.playerNeedsReopen }
        #expect(!sut.status.playerNeedsReopen)
        #expect(shown.calls == ["Reopen Radio?", "Reopen Radio?"])
        #expect(ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))
    }
}
