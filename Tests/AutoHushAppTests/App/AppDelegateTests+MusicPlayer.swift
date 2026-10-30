import AppKit
import CheckedPlayers
import Foundation
import os
import SwiftUI
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

extension AppDelegateTests {
    // MARK: - Music player

    @MainActor
    @Test("with no player chosen, AutoHush waits for one and offers them all")
    func waitsForPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        #expect(sut.status.statusLine == "Choose a media player")
        #expect(sut.status.playerOptions.map(\.name) == ["First", "Second"])
        #expect(sut.settingsModel.playerOptions == sut.status.playerOptions)
        #expect(sut.settingsModel.chosenPlayerID == nil)
    }

    @MainActor
    @Test("with no supported player installed, AutoHush asks for one, and none can be chosen until one is")
    func noPlayerInstalled() {
        let scratch = Scratch()
        scratch.installed = []
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        #expect(!sut.status.playerOptions.isEmpty && sut.status.playerOptions.allSatisfy { !$0.isInstalled })

        sut.choosePlayer(Players.first)
        #expect(sut.player == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(monitorings.made.isEmpty)

        // Installed later: it can be chosen.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
        sut.choosePlayer(Players.first)
        #expect(sut.player?.bundleID == Players.first)
    }

    @MainActor
    @Test("choosing a player stores it, shows it and starts over with it; choosing it again does nothing")
    func choosePlayer() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch, chosenPlayer: nil)
        sut.session.launch() // nothing to start yet

        sut.choosePlayer(Players.second)
        #expect(scratch.preferences.musicPlayer == Players.second)
        #expect(sut.status.playerName == "Second")
        #expect(!sut.settingsModel.playerCanFade) // its fade settings are dimmed
        #expect(sut.settingsModel.chosenPlayerName == "Second")
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.settingsModel.chosenPlayerID == Players.second)
        #expect(sut.status.health == .starting)
        await TestWait.until { sut.status.health == .ready }
        #expect(monitorings.made.map(\.bundleID) == [Players.second])

        sut.choosePlayer(Players.second)
        await sut.session.waitUntilIdle()
        #expect(monitorings.made.count == 1)

        sut.choosePlayer(Players.first)
        #expect(sut.status.playerName == "First")
        #expect(sut.settingsModel.playerCanFade)
        await TestWait.until { monitorings.made.count == 2 }
        #expect(monitorings.made.map(\.bundleID) == [Players.second, Players.first])
    }

    /// A player only its sound tells about (`needsAudioLevels`), as an app
    /// added with Add an App can be.
    private struct HeardPlayer: MusicPlayer {
        static let id = "com.example.heard"
        let bundleID = Self.id
        let name = "Heard"
        let stateReportDelay: TimeInterval = 0
        var needsAudioLevels: Bool { true }
        func verifyControlAccess() async throws {}
        func playerState() async -> PlayerState { .playing }
        func pause() async throws {}
        func play() async throws {}
        func volume() async -> Int? { nil }
        func setVolume(_ volume: Int) async throws {}
        @MainActor
        func makeStateObserver(onChange: @escaping @MainActor (PlayerState) -> Void) -> any PlayerStateObserving {
            MockStateObserver()
        }
    }

    @MainActor
    @Test("a player that isn't installed, isn't supported, or in AntiDot mode is told only by its sound, can't be chosen")
    func chooseUnavailablePlayer() {
        let scratch = Scratch()
        scratch.installed = [Players.first, HeardPlayer.id]
        scratch.players = MusicPlayerCatalog(players: [scratch.first, scratch.second, HeardPlayer()], formerDefault: Players.first)
        scratch.preferences.detectionMethod = .playbackSignals // AntiDot mode
        let (sut, monitorings) = makeSUT(scratch)

        sut.choosePlayer(Players.second)
        sut.choosePlayer("com.example.unknown")
        sut.choosePlayer(HeardPlayer.id)
        #expect(sut.player?.bundleID == Players.first)
        #expect(scratch.preferences.musicPlayer == Players.first)
        #expect(monitorings.made.isEmpty)
    }

    @MainActor
    @Test("another supported player opening shows it as installed, without starting over")
    func otherPlayerLaunch() async {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)

        scratch.installed.insert(Players.second)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.status.playerOptions.map(\.isInstalled) == [true, true])
        await sut.session.waitUntilIdle()
        #expect(sut.status.health == .ready)
        #expect(monitorings.made.count == 1)
    }

    @MainActor
    @Test("while no player is chosen, a supported player opening brings the welcome window back")
    func playerLaunchWhileWaiting() {
        let (sut, monitorings) = makeSUT(chosenPlayer: nil)
        #expect(!sut.isShowingPlayerChooser)

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.isShowingPlayerChooser)
        #expect(monitorings.made.isEmpty)

        sut.choosePlayer(Players.second)
        // It goes on to what the player needs, and closes once done.
        #expect(sut.isShowingPlayerChooser)
        #expect(sut.settingsModel.welcomeAsksPermissions)
        sut.finishWelcome()
        #expect(!sut.isShowingPlayerChooser)
        #expect(!sut.settingsModel.welcomeAsksPermissions)
    }

    @MainActor
    @Test("opening the menu brings the welcome window forward while it's open, in case other windows covered it")
    func menuBringsWelcomeForward() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 0) // not open

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second) // brings the welcome window
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 1)

        scratch.chooser.close()
        sut.menuWillOpen()
        #expect(scratch.chooser.broughtForward == 1)
    }

    @MainActor
    @Test("the menu says when the player plays silently, and a mute in place of the pause")
    func menuSaysPlayingSilently() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let monitoring = monitorings.made[0]
        monitoring.send(.playback(.playingSilently))
        #expect(sut.status.statusLine == "Playing silently")
        monitoring.send(.playback(.pausedByMonitor))
        monitoring.send(.mutedInstead(true))
        #expect(sut.status.playerMutedInstead && sut.status.statusLine == "Muted — another app is playing")
    }

    @MainActor
    @Test("the chosen player is left out of Settings → Sound Sources and the ignored apps")
    func chosenPlayerNotListedAsApp() {
        let scratch = Scratch()
        let first = AudioSource(id: Players.first, name: "First")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        scratch.preferences.recordSeen([first, vlc])
        scratch.preferences.ignoredApps = [first]
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.appList.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.status.ignoredApps.isEmpty)

        // Once another player is chosen, it's an app like any other.
        sut.choosePlayer(Players.second)
        #expect(sut.settingsModel.appList.apps.map(\.id) == [Players.first, "org.videolan.vlc"])
        #expect(sut.status.ignoredApps == [first])
    }

    @MainActor
    @Test("someone updating from before the choice keeps the former player, unasked")
    func updatingKeepsFormerPlayer() {
        let scratch = Scratch()
        scratch.preferences.lastLaunchedVersion = "0.3.11"
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.player?.bundleID == Players.first)
        #expect(sut.status.health == .starting)
    }

    @MainActor
    @Test("a stored player that is no longer supported is asked for again")
    func unknownStoredPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: "com.example.gone")
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a media player"))
    }

    @MainActor
    @Test("Diagnostics in Settings is read once asked for: no app with sound yet, the chosen player and the permission it needs")
    func diagnosticsRead() async {
        let (sut, _) = makeSUT()
        #expect(sut.settingsModel.diagnostics == nil)
        await sut.refresh(.diagnostics)
        let diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.isEmpty == true)
        #expect(diagnostics?.text.contains("Apps with Sound\nNo other app is playing sound right now.") == true)
        #expect(diagnostics?.sections.first?.rows.first?.value.hasPrefix("First") == true)
        #expect(diagnostics?.text.contains("Automation for First") == true)
    }

    @MainActor
    @Test("Diagnostics in Settings lists the apps with sound, found where Settings → Sound Sources lists them")
    func diagnosticsAppsWithSound() async {
        let scratch = Scratch()
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        scratch.preferences.recordSeen([vlc])
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        monitorings.made[0].audioReport = [ActiveAudioReport.Entry(id: vlc.id, name: "VLC", state: .playing)]
        await sut.refresh(.diagnostics)
        let diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.map(\.bundlePath) == [vlc.bundlePath])
        #expect(diagnostics?.text.contains("Apps with Sound\nVLC (org.videolan.vlc) — playing") == true)
    }

    @MainActor
    @Test("Diagnostics in Settings says the ways an app added with Add an App is controlled by")
    func diagnosticsAddedAppWays() {
        let scratch = Scratch()
        let setup = PlayerSetup(bundleID: "com.example.added", name: "Added", appURL: URL(fileURLWithPath: "/Applications/Added.app"),
                                ways: [.menu(menuName: "Controls")])
        let checked = CheckedPlayer(setup: setup, reports: nil)
        scratch.players = MusicPlayerCatalog(players: [scratch.first], found: { [checked] })
        scratch.installed.insert(setup.bundleID)
        let (sut, _) = makeSUT(scratch, chosenPlayer: setup.bundleID)
        sut.refreshDiagnostics()
        #expect(sut.settingsModel.diagnostics?.text.contains("Controlled by: \(WayText.title(.menu))") == true)
    }

    @MainActor
    @Test("the window watch's refresh of launch at login shows it switched on in System Settings")
    func launchAtLoginRefreshed() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        scratch.launchAtLogin.isEnabled = true // in System Settings
        await sut.refresh(.launchAtLogin)
        #expect(sut.settingsModel.launchAtLoginEnabled)
    }

    @MainActor
    @Test("while Settings is open, the window watch follows launch at login and the permissions, Diagnostics on its page, and the players while none is chosen")
    func settingsNeedsByPage() {
        #expect(AppDelegate.settingsNeeds(page: .general, hasPlayer: true) == [.notifications, .launchAtLogin, .permissions])
        #expect(AppDelegate.settingsNeeds(page: .diagnostics, hasPlayer: false)
                == [.notifications, .launchAtLogin, .permissions, .diagnostics, .players])
    }

    @MainActor
    @Test("only the chosen player is ever asked for permission to control it, and only once chosen")
    func onlyChosenPlayerIsAsked() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil)
        sut.session.launch()

        // Nothing is asked before a player is chosen, not even when one opens.
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await sut.session.waitUntilIdle()
        #expect(await scratch.first.verifyCallCount == 0)
        #expect(await scratch.second.verifyCallCount == 0)

        sut.choosePlayer(Players.second) // also closes the welcome window
        await TestWait.until { sut.status.health != .starting }
        #expect(sut.status.health == .ready)
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(await scratch.first.verifyCallCount == 0)
    }

    @MainActor
    @Test("a chosen player that was uninstalled is reported as not installed")
    func chosenPlayerUninstalled() async {
        let scratch = Scratch()
        scratch.installed = []
        // The start stops at the install check, before scripting the player.
        let (sut, _) = makeSUT(scratch)
        sut.session.launch()
        await sut.session.waitUntilIdle()
        #expect(sut.status.health == .degraded("First isn’t installed"))

        // Installed again: it's controlled afresh as soon as AutoHush notices.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        await TestWait.until { sut.status.health == .ready }
        #expect(await scratch.first.verifyCallCount == 1)
    }

    /// First can't be controlled at its start: Play/Pause isn't in its
    /// menus. AutoHush's alerts are noted with their texts and buttons, and
    /// answered OK (System Settings stays closed).
    @MainActor
    private func controlFailed() async -> (scratch: Scratch, sut: AppDelegate, alerts: CallLog) {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerCommandFailed(.menuItemNotFound))
        let (sut, _) = makeSUT(scratch)
        let alerts = CallLog()
        sut.runAlert = { alert in
            alerts.calls.append(([alert.messageText, alert.informativeText] + alert.buttons.map(\.title)).joined(separator: " | "))
            return .alertSecondButtonReturn // OK: System Settings stays closed
        }
        sut.session.launch()
        await TestWait.until { sut.status.health != .starting }
        return (scratch, sut, alerts)
    }

    @MainActor
    @Test("why the player session can't control the player shows in the menu and Settings")
    func controlErrorShown() async {
        let (_, sut, _) = await controlFailed()
        #expect(sut.status.statusLine == "Can’t control First right now")
        #expect(sut.settingsModel.statusLine == "Can’t control First right now")
        #expect(sut.status.controlError?.text == "AutoHush can’t find Play/Pause in First’s menus.")
    }

    @MainActor
    @Test("the info button after why the player can't be controlled has an alert say what failed, then why, with OK only")
    func controlErrorAlert() async {
        let (_, sut, alerts) = await controlFailed()
        sut.showControlError() // the info button after the card's line
        #expect(alerts.calls.count == 1)
        #expect(alerts.calls.first?.hasPrefix("Can’t Control First | AutoHush can’t find Play/Pause in First’s menus.") == true)
        // The log's English after it only when AutoHush speaks another language.
        #expect(alerts.calls.first?.contains("\n\n") == !AppStatus.speaksEnglish)
        #expect(alerts.calls.first?.contains(ControlFailure.openMenuBarSettings) == false)
    }

    @MainActor
    @Test("why the player can't be controlled, Now Playing hidden in the menu bar, has its alert offer the pane that shows it")
    func controlErrorAlertOffersPane() async {
        let (_, sut, alerts) = await controlFailed()
        sut.status.controlError = ControlError(MusicPlayerError.playerCommandFailed(.nowPlayingHidden), player: "First")
        sut.showControlError()
        #expect(alerts.calls.last?.hasSuffix(" | \(ControlFailure.openMenuBarSettings) | OK") == true)
    }

    @MainActor
    @Test("the info button after “Couldn’t resume” has its alert offer Try Again (Return), which resumes once more")
    func resumeFailedAlertOffersTryAgain() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let alerts = CallLog()
        sut.runAlert = { alert in
            alerts.calls.append(([alert.messageText] + alert.buttons.map(\.title)).joined(separator: " | "))
            return .alertFirstButtonReturn // Try Again
        }
        monitorings.made[0].send(.resumeFailure(.playerNotResponding))
        await TestWait.until { sut.status.showsResumeFailure }
        sut.showControlError()
        #expect(alerts.calls.last?.hasSuffix(" | Try Again | OK") == true)
        #expect(monitorings.made[0].resumeRetries == 1)
    }

    @MainActor
    @Test("Unmute on a player muted in place of its pause lifts AutoHush's own mute through the session")
    func unmuteInsteadThroughSession() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        monitorings.made[0].send(.playback(.pausedByMonitor))
        monitorings.made[0].send(.mutedInstead(true))
        await TestWait.until { sut.status.playerMutedInstead }
        sut.unmutePlayer()
        #expect(monitorings.made[0].unmutesInstead == 1)
    }

    @MainActor
    @Test("why the player session can't control the player goes once the player is controlled")
    func controlErrorGoes() async {
        let (scratch, sut, _) = await controlFailed()
        await scratch.first.setFailVerify(nil)
        await TestWait.until { sut.status.health == .ready }
        #expect(sut.status.controlError == nil)
    }

    @MainActor
    @Test("what the player session knows of the music and the apps playing shows in the menu, and in Settings → Sound Sources")
    func musicAndAppsShown() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        monitorings.made[0].send(.playback(.pausedByMonitor))
        monitorings.made[0].send(.activeSources([vlc]))
        #expect(sut.status.playback == .pausedByMonitor)
        #expect(sut.status.activeSources == [vlc])
        #expect(sut.settingsModel.appList.apps.map(\.id) == [vlc.id]) // listed in Settings → Sound Sources as it plays
    }

    @MainActor
    @Test("a pause the player session holds is no moment for an update's restart")
    func heldPauseIsNoQuietMoment() async {
        let scratch = Scratch()
        scratch.windowOpen = false
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        #expect(sut.isQuietMoment)
        monitorings.made[0].send(.playback(.pausedByMonitor))
        #expect(!sut.isQuietMoment) // it holds a pause: no restart for an update now
    }

    @MainActor
    @Test("while Add an App's check runs, the player session's pause is held until the check ends, and the menu says so")
    func pauseHeldForCheck() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        monitorings.made[0].send(.playback(.pausedByMonitor))
        monitorings.made[0].send(.activeSources([AudioSource(id: "org.videolan.vlc", name: "VLC")]))
        sut.holdsPlayerForCheck(true)
        sut.holdsPlayerForCheck(true) // again: nothing more
        #expect(sut.session.resumesHeld && monitorings.made[0].resumesHeld == [true])
        #expect(sut.status.statusLine == "Paused while a check runs")
        sut.holdsPlayerForCheck(false)
        #expect(!sut.session.resumesHeld && monitorings.made[0].resumesHeld == [true, false])
        #expect(!sut.status.playerHeldForCheck)
    }

    @MainActor
    @Test("the apps that played show in the menu's Recently Played, those playing as another player is chosen too")
    func recentlyPlayedShown() async {
        let (sut, monitorings) = makeSUT()
        await start(sut)
        // VLC stops: Recently Played lists it. Safari plays as another
        // player is chosen, which stops the monitoring: Safari too.
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        monitorings.made[0].send(.activeSources([vlc]))
        monitorings.made[0].send(.activeSources([]))
        #expect(sut.status.recentSources() == [vlc])
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        monitorings.made[0].send(.activeSources([safari]))
        sut.choosePlayer(Players.second)
        #expect(sut.status.activeSources.isEmpty)
        #expect(sut.status.recentSources() == [safari, vlc])
    }

    @MainActor
    @Test("the chosen player uninstalled while AutoHush runs is noticed without a restart, and put back starts it again")
    func playerUninstalledWhileRunning() async {
        let scratch = Scratch()
        let (sut, monitorings) = makeSUT(scratch)
        await start(sut)
        monitorings.made[0].send(.playback(.musicPlaying))

        // Moved to the Trash: its folder changes, and nothing else happens.
        scratch.installed = []
        scratch.changeFolder()
        await TestWait.until { sut.status.health != .ready }
        #expect(sut.status.health == .degraded("First isn’t installed"))
        #expect(sut.status.playback == .unknown)
        #expect(monitorings.made[0].isStopped)

        // Put back: controlled afresh.
        scratch.installed = [Players.first]
        scratch.changeFolder()
        await TestWait.until { sut.status.health == .ready }
        #expect(monitorings.made.count == 2)
    }

    @MainActor
    @Test("opening the menu notices a player that was uninstalled while it wasn't running")
    func menuNoticesUninstalledPlayer() async {
        let scratch = Scratch()
        await scratch.first.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, monitorings) = makeSUT(scratch)
        sut.session.launch()
        await TestWait.until { sut.status.health == .playerClosed("First isn’t running") }

        scratch.installed = []
        sut.refreshPlayerOptions() // what opening the menu or Settings does
        #expect(sut.status.health == .degraded("First isn’t installed"))
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == false)

        // Asked again, it stays as it is.
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .degraded("First isn’t installed"))
        // Only what listed the apps while it wasn't running, stopped now.
        #expect(monitorings.made.count == 1 && monitorings.made.allSatisfy(\.isStopped))
    }

    @MainActor
    @Test("the Applications folders are watched, and the one holding the chosen player's app")
    func watchesApplicationFolders() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let applicationFolders = Set(ApplicationFolders.all.map(\.path))
        #expect(sut.watchedFolders == applicationFolders)

        sut.choosePlayer(Players.second) // in a folder inside /Applications
        #expect(sut.watchedFolders == applicationFolders.union(["/Applications/Players"]))

        // Gone: the Applications folders are enough to notice it coming back.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.watchedFolders == applicationFolders)
    }

    @MainActor
    @Test("with no player chosen, no folder is watched")
    func noWatchWithoutPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        sut.refreshPlayerOptions()
        #expect(sut.watchedFolders.isEmpty)
    }
}
