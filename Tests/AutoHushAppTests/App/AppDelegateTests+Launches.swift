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

    /// macOS's notices come on NSWorkspace's own center, which every
    /// AppDelegate that registered its observers hears: these tests run one
    /// at a time, each AppDelegate quitting at its end, so only the test's
    /// own observes them.
    @MainActor
    @Suite("macOS's notices", .serialized)
    struct WorkspaceNotices {
        private let tests = AppDelegateTests()
        private let center = NSWorkspace.shared.notificationCenter

        /// AutoHush launched with First chosen, running or not, following
        /// macOS's notices.
        private func observing(_ scratch: Scratch = Scratch(), running: Bool) async -> (AppDelegate, FakeMonitorings) {
            if !running { await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning) }
            let (sut, monitorings) = tests.makeSUT(scratch)
            sut.session.launch()
            let health: AppHealthState = running ? .ready : .degraded("First isn’t running")
            await TestWait.until { sut.status.health == health }
            sut.registerPlayerLaunchObserver()
            sut.registerSleepObservers()
            return (sut, monitorings)
        }

        private func launch(_ app: FakeRunningApplication) {
            center.post(name: NSWorkspace.didLaunchApplicationNotification, object: nil,
                        userInfo: [NSWorkspace.applicationUserInfoKey: app])
        }

        private func quit(_ sut: AppDelegate) {
            sut.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        @Test("AutoHush follows the apps that open with one observer, however often it's asked to")
        func launchObserverOnce() {
            let (sut, _) = tests.makeSUT()
            defer { quit(sut) }
            sut.registerPlayerLaunchObserver()
            let observer = sut.playerLaunchObserver
            sut.registerPlayerLaunchObserver() // once only
            #expect(observer != nil && sut.playerLaunchObserver === observer)
        }

        @Test("macOS telling the chosen player opened starts it again")
        func playerOpened() async {
            let scratch = Scratch()
            let (sut, monitorings) = await observing(scratch, running: false)
            defer { quit(sut) }
            await scratch.first.setFailVerify(nil)
            launch(FakeRunningApplication(bundleID: Players.first))
            await TestWait.until { sut.status.health == .ready }
            #expect(monitorings.made.count == 2) // the one listing the apps while it was closed, then its own
        }

        @Test("macOS telling an app that plays only the volume sound opened has it ignored")
        func volumeSoundAppOpened() async throws {
            let (sut, _) = await observing(running: true)
            defer { quit(sut) }
            // BetterDisplay opened (an app on the disk: a running app's bundle names it).
            let folder = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: folder) }
            let betterDisplay = try TestAppBundle.make(in: folder, name: "BetterDisplay", info: ["CFBundleIdentifier": "pro.betterdisplay.BetterDisplay"])
            launch(FakeRunningApplication(bundleID: "pro.betterdisplay.BetterDisplay", bundleURL: betterDisplay))
            await TestWait.until { !sut.userSettings.state.ignoredApps.isEmpty }
            #expect(sut.userSettings.state.ignoredApps.map(\.id) == ["pro.betterdisplay.BetterDisplay"])
        }

        @Test("macOS telling the Mac sleeps and wakes, or only its screens wake, reaches the session")
        func sleepAndWake() async {
            let (sut, monitorings) = await observing(running: true)
            defer { quit(sut) }
            for (notice, asleep) in [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false),
                                     (NSWorkspace.willSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
                center.post(name: notice, object: nil)
                await TestWait.until { sut.session.isAsleep == asleep }
            }
            #expect(monitorings.made.last?.asleep == [true, false, true, false])
        }

        @Test("once AutoHush quits, it no longer follows macOS's notices: the chosen player opening does nothing")
        func quitStopsFollowing() async {
            let scratch = Scratch()
            let (sut, monitorings) = await observing(scratch, running: false)
            await scratch.first.setFailVerify(nil)
            quit(sut)
            #expect(sut.playerLaunchObserver == nil && sut.sleepObservers.isEmpty)
            launch(FakeRunningApplication(bundleID: Players.first))
            await Task.yield() // what a notice still observed would start
            await sut.session.waitUntilIdle()
            #expect(monitorings.made.count == 1) // not started again
        }
    }

    // MARK: - A player opened without what it needs

    /// Tunes, which the user chose to reopen always (the alert's box) and
    /// which drops the option it needs again when reopened (a launcher), and
    /// Radio, which needs reopening once; `chosen` is chosen at launch.
    @MainActor
    private func reopenBench(chosen: String?) async -> (scratch: Scratch, tunes: MockMusicPlayer, radio: MockMusicPlayer, sut: AppDelegate) {
        let scratch = Scratch()
        let tunes = MockMusicPlayer(bundleID: "com.example.tunes", name: "Tunes")
        let radio = MockMusicPlayer(bundleID: "com.example.radio", name: "Radio")
        await tunes.setNeedsReopening(true, afterReopen: true) // a launcher that drops the option
        await radio.setNeedsReopening(true)
        scratch.players = MusicPlayerCatalog(players: [tunes, radio])
        scratch.installed = [tunes.bundleID, radio.bundleID]
        ReopenChoices.setReopensAlways(tunes.bundleID, defaults: scratch.defaults)
        let (sut, _) = makeSUT(scratch, chosenPlayer: chosen)
        return (scratch, tunes, radio, sut)
    }

    /// Radio chosen without asking: reopening it was just skipped in Add an App.
    @MainActor
    private func radioChosenUnasked() async -> (scratch: Scratch, radio: MockMusicPlayer, sut: AppDelegate) {
        let (scratch, _, radio, sut) = await reopenBench(chosen: nil)
        sut.chooseMusicPlayer(radio.bundleID, asksToReopen: false)
        await TestWait.until { sut.status.playerNeedsReopen }
        return (scratch, radio, sut)
    }

    /// AutoHush's alerts answered with `answer`, their box ticked; their titles noted.
    @MainActor
    private func answerAlerts(_ sut: AppDelegate, with answer: NSApplication.ModalResponse) -> CallLog {
        let shown = CallLog()
        sut.runAlert = { alert in
            shown.calls.append(alert.messageText)
            alert.suppressionButton?.state = .on
            return answer
        }
        return shown
    }

    @MainActor
    @Test("a player opened without the option it needs, which the user chose to reopen always, is reopened at once")
    func reopenedAtOnce() async {
        let (_, tunes, _, sut) = await reopenBench(chosen: "com.example.tunes")
        await TestWait.until { sut.status.playerNeedsReopen }
        #expect(await tunes.reopenCount == 1)
    }

    /// Tunes, chosen and reopened at once, then found without its option
    /// again within a minute of being reopened: given up on this time.
    @MainActor
    private func tunesGivenUpOn() async -> (scratch: Scratch, tunes: MockMusicPlayer, sut: AppDelegate) {
        let (scratch, tunes, _, sut) = await reopenBench(chosen: "com.example.tunes")
        await TestWait.until { sut.status.playerNeedsReopen } // reopened at once
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        await TestWait.until { sut.lastReopens[tunes.bundleID]?.gaveUp == true } // given up this time
        return (scratch, tunes, sut)
    }

    @MainActor
    @Test("a player to reopen always, found without its option again within a minute of being reopened, isn't reopened again: only the card says so")
    func reopenedOnlyOnceAMinute() async {
        let (_, tunes, sut) = await tunesGivenUpOn()
        #expect(await tunes.reopenCount == 1)
        #expect(sut.status.playerNeedsReopen)
    }

    @MainActor
    @Test("a player to reopen always, given up on within a minute of being reopened, is reopened by itself again when found so over a minute later")
    func reopenedAgainAfterAMinute() async {
        let (scratch, tunes, sut) = await tunesGivenUpOn()
        scratch.clock.advance(by: 61)
        sut.handleApplicationDidLaunch(bundleIdentifier: tunes.bundleID)
        await TestWait.until { await tunes.reopenCount == 2 }
    }

    @MainActor
    @Test("the card's Reopen reopens a player that needs it")
    func cardReopens() async {
        let (_, tunes, _, sut) = await reopenBench(chosen: "com.example.tunes")
        await TestWait.until { sut.status.playerNeedsReopen } // reopened at once, and without its option again
        await tunes.setNeedsReopening(true)
        sut.reopenChosenPlayer() // the card's Reopen
        await TestWait.until { !sut.status.playerNeedsReopen }
        #expect(await tunes.reopenCount == 2)
    }

    @MainActor
    @Test("a player opened without the option it needs, chosen without asking (reopening it was just skipped in Add an App), is left to the card")
    func reopenLeftToTheCard() async {
        let (_, _, radio, sut) = await reopenBench(chosen: nil)
        sut.chooseMusicPlayer(radio.bundleID, asksToReopen: false)
        await TestWait.until { sut.status.playerNeedsReopen }
        #expect(await radio.reopenCount == 0)
    }

    @MainActor
    @Test("a player that needs reopening, as it's chosen, is asked about: Reopen (Return) or Cancel (Escape), and a box to reopen it so always")
    func reopenAlert() {
        let alert = AppDelegate.reopenAlert("Radio")
        #expect(alert.messageText == "Reopen Radio?")
        #expect(alert.buttons.map(\.title) == ["Reopen Radio", "Cancel"])
        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
        #expect(alert.showsSuppressionButton && alert.suppressionButton?.title == "Always reopen Radio this way")
    }

    @MainActor
    @Test("asked about reopening a player just chosen, Cancel leaves it to the card, the box ticked or not")
    func reopenCancelled() async {
        let (scratch, radio, sut) = await radioChosenUnasked()
        let shown = answerAlerts(sut, with: .alertSecondButtonReturn) // Cancel
        sut.chooseMusicPlayer(radio.bundleID, replacing: true) // checked again in Add an App, and used
        await TestWait.until { shown.calls.count == 1 }
        #expect(await radio.reopenCount == 0)
        #expect(sut.status.playerNeedsReopen)
        #expect(!ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))
        #expect(shown.calls == ["Reopen Radio?"])
    }

    @MainActor
    @Test("asked about reopening a player just chosen, Reopen with the box ticked reopens it, and from then on without asking")
    func reopenedAlways() async {
        let (scratch, radio, sut) = await radioChosenUnasked()
        let shown = answerAlerts(sut, with: .alertFirstButtonReturn) // Reopen
        sut.chooseMusicPlayer(radio.bundleID, replacing: true) // checked again in Add an App, and used
        await TestWait.until { await radio.reopenCount == 1 }
        await TestWait.until { !sut.status.playerNeedsReopen }
        #expect(shown.calls == ["Reopen Radio?"])
        #expect(ReopenChoices.reopensAlways(radio.bundleID, defaults: scratch.defaults))
    }
}
