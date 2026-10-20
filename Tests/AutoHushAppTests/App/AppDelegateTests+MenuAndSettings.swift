import AppKit
import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

extension AppDelegateTests {
    // MARK: - The menu

    /// AutoHush's menu bar menu, with notification centers of its own: no
    /// other test's window becoming key closes it.
    @MainActor
    private func statusMenu(_ sut: AppDelegate) throws -> StatusMenuController {
        sut.showStatusMenu()
        let menu = try #require(sut.statusMenu)
        menu.notificationCenter = NotificationCenter()
        menu.workspaceCenter = NotificationCenter()
        return menu
    }

    @MainActor
    @Test("the menu shows the app's status")
    func menuShowsStatus() async throws {
        let (sut, _) = makeSUT()
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        await start(sut)
        #expect(menu.status == sut.status)
    }

    @MainActor
    @Test("the menu's items reach AutoHush's own settings: auto-pause and the ignored apps")
    func menuReachesSettings() async throws {
        let (sut, _) = makeSUT()
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        await start(sut)
        menu.perform(.toggleAutoPause)
        #expect(!sut.userSettings.state.autoPauseActive)
        #expect(sut.status.autoPause == .off && menu.status.autoPause == .off)

        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        menu.perform(.setIgnored(vlc, true))
        #expect(sut.session.settings.ignored == [vlc.id])
        #expect(menu.status.ignoredApps == [vlc])
    }

    @MainActor
    @Test("while the menu is open, an update doesn't restart AutoHush")
    func openMenuIsNoQuietMoment() async throws {
        let scratch = Scratch()
        scratch.windowOpen = false
        let (sut, _) = makeSUT(scratch)
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        await start(sut)
        #expect(sut.isQuietMoment)
        menu.open(showsPanel: false)
        #expect(!sut.isQuietMoment) // the menu is open
    }

    @MainActor
    @Test("a player chosen from the menu's list is AppDelegate's to choose, in place: the menu stays open")
    func menuChoosesPlayer() async throws {
        let (sut, _) = makeSUT()
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        await start(sut)
        menu.open(showsPanel: false)
        menu.perform(.openSide(.players))
        #expect(menu.model.players.supportedApps.contains { $0.id == Players.second })
        menu.perform(.choosePlayer(Players.second)) // chosen in place: the menu stays open
        await TestWait.until { sut.player?.bundleID == Players.second }
        #expect(menu.status.chosenPlayerID == Players.second)
        #expect(menu.isMenuOpen && !menu.model.isChoosingPlayer)
        menu.close()
    }

    @MainActor
    @Test("the menu's Retry, once a start failed, is the player session's")
    func menuRetries() async throws {
        let scratch = Scratch()
        await scratch.second.setFailVerify(MusicPlayerError.playerNotResponding)
        let (sut, _) = makeSUT(scratch, chosenPlayer: Players.second)
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        sut.session.launch()
        await TestWait.until { sut.status.canRetry } // its start failed
        menu.perform(.retry)
        #expect(sut.status.health == .starting && menu.status.health == .starting)
    }

    @MainActor
    @Test("the menu card's chips reach the player itself: Unmute plays it, Reopen reopens it")
    func menuReachesPlayer() async throws {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: Players.second)
        let menu = try statusMenu(sut)
        defer { menu.remove() }
        menu.perform(.unmutePlayer)
        await TestWait.until { await scratch.second.playCallCount == 1 }
        menu.perform(.reopenPlayer)
        await TestWait.until { await scratch.second.reopenCount == 1 }
    }

    // MARK: - Settings and updates

    @MainActor
    @Test("the user's settings show in the menu and Settings, and reach the monitoring")
    func userSettingsShown() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        let monitoring = monitorings.made[0]
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.userSettings.snooze(.oneHour)
        guard case .snoozed = sut.status.autoPause else {
            Issue.record("expected snoozed, got \(sut.status.autoPause)")
            return
        }
        #expect(!sut.settingsModel.isAutoPauseOn)
        #expect(sut.settingsModel.autoPauseNote?.hasPrefix("Turned off until") == true)
        #expect(monitoring.autoPause == false)
        sut.userSettings.setAutoPause(true)
        #expect(sut.settingsModel.isAutoPauseOn && sut.settingsModel.autoPauseNote == nil)
        #expect(monitoring.autoPause == true)

        sut.userSettings.setIgnored(vlc, true)
        #expect(sut.status.ignoredApps == [AudioSource(id: vlc.id, name: "VLC")])
        #expect(sut.settingsModel.appList.apps.map(\.id) == [vlc.id])
        #expect(sut.settingsModel.appList.apps.first?.isIgnored == true)
        #expect(monitoring.ignored == [vlc.id])

        sut.userSettings.setTimings(TimingSettings(stopGrace: 4))
        #expect(sut.settingsModel.timings.stopGrace == 4)
        #expect(monitoring.configurations.last?.sourceStopGrace == 4)
        sut.userSettings.setDetectionMethod(.playbackSignals)
        #expect(sut.settingsModel.detectionMethod == .playbackSignals)
        #expect(monitoring.detectionMethods == [.playbackSignals])
    }

    @MainActor
    @Test("with nothing monitored, quitting doesn't wait")
    func quittingIdle() {
        let (idle, _) = makeSUT()
        #expect(idle.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @MainActor
    @Test("while a player is monitored, the quit goes on once its volume is back")
    func quitting() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let replies = CallLog()
        #expect(sut.shouldTerminate(wait: 60) { replies.calls.append("after \(monitorings.made[0].restoredStops) stop") }
                == .terminateLater)
        await sut.quitting?.value
        #expect(replies.calls == ["after 1 stop"]) // the volume back first
    }

    /// An added app chosen that doesn't let go of what it turned on in its
    /// app, and a quit that waits 0.05 s for it: gone on after the wait.
    @MainActor
    private func quitPastAStuckStop() async -> (added: MockMusicPlayer, sut: AppDelegate, replies: CallLog) {
        let scratch = Scratch()
        let added = MockMusicPlayer(bundleID: "com.example.added", name: "Added", canFade: false, kind: .checkedApp, releasesOnQuit: true)
        await added.holdReleases()
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [added] })
        scratch.installed.insert(added.bundleID)
        let (stuck, _) = makeSUT(scratch, chosenPlayer: added.bundleID)
        let stuckReplies = CallLog()
        #expect(stuck.shouldTerminate(wait: 0.05) { stuckReplies.calls.append("reply") } == .terminateLater)
        await TestWait.until { stuckReplies.calls.count == 1 } // after the wait
        return (added, stuck, stuckReplies)
    }

    @MainActor
    @Test("a stop that never ends lets the quit go on after the wait")
    func quittingPastAStuckStop() async {
        let (added, _, _) = await quitPastAStuckStop()
        #expect(await added.releases == 0)
    }

    @MainActor
    @Test("a stop that ends after the quit went on without it doesn't let the quit go on a second time")
    func quittingOnceOnly() async {
        let (added, stuck, stuckReplies) = await quitPastAStuckStop()
        await added.letGo()
        await stuck.quitting?.value
        #expect(stuckReplies.calls.count == 1) // not twice
        #expect(await added.releases == 1)
    }

    @MainActor
    @Test("an update restarts AutoHush only at a quiet moment: no pause held, the menu closed, and none of its windows or alerts open")
    func quietMoment() async throws {
        let scratch = Scratch()
        scratch.windowOpen = false
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        #expect(sut.isQuietMoment)

        scratch.windowOpen = true // Settings, say
        #expect(!sut.isQuietMoment)
        scratch.windowOpen = false
        monitorings.made[0].send(.playback(.pausedByMonitor)) // a pause held
        #expect(!sut.isQuietMoment)
        monitorings.made[0].send(.playback(.musicPlaying))
        #expect(sut.isQuietMoment)

        sut.showStatusMenu()
        let menu = try #require(sut.statusMenu)
        defer { menu.remove() }
        menu.notificationCenter = NotificationCenter()
        menu.workspaceCenter = NotificationCenter()
        menu.open(showsPanel: false)
        #expect(!sut.isQuietMoment)
        menu.close()
        #expect(sut.isQuietMoment)
    }

    @MainActor
    @Test("a newer release found by an update check is offered in the menu and Settings")
    func updateAvailable() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, updateChecker: .latestRelease("v0.3.0"))
        #expect(sut.settingsModel.currentVersion == "0.2.0")
        #expect(sut.settingsModel.lastUpdateCheck == nil)
        await sut.updates.check(userInitiated: false)
        #expect(sut.status.updateOffer == UpdateOffer(release: sut.updates.availableUpdate!, state: .available))
        #expect(sut.settingsModel.updateStatus == "Version 0.3.0 is available.")
        #expect(sut.settingsModel.updateTitle == "Version 0.3.0 is available.")
        #expect(sut.settingsModel.lastUpdateCheck == scratch.preferences.lastUpdateCheck)
        #expect(sut.settingsModel.lastUpdateCheck != nil)
    }

    @MainActor
    @Test("the update settings show in Settings as they're changed; the choice starts at installing")
    func updateSettingsShown() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(sut.settingsModel.updateInstallNote == nil)
        sut.updates.setMode(.download)
        #expect(sut.settingsModel.automaticUpdates == .download)
        sut.updates.setChecksAutomatically(false)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
    }

    @MainActor
    @Test("Settings says why AutoHush can't update itself")
    func installUnavailableNote() {
        let (sut, _) = makeSUT(updateInstaller: MockUpdateInstaller(unavailability: .readOnlyLocation))
        #expect(sut.settingsModel.updateInstallNote == "AutoHush can’t update itself, because it can’t write to the folder it’s in.")
    }
}
