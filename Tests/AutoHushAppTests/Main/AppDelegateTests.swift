import AppKit
import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

@Suite("AppDelegate")
struct AppDelegateTests {
    /// Counts bootstrap requests; the real bootstrap would script the music
    /// player and tap real audio processes from inside the test process.
    @MainActor
    private final class BootstrapCounter {
        var count = 0
    }

    /// In-memory preferences and a downloads folder of its own, so tests
    /// never write preference files or touch AutoHush's real Caches. Two
    /// stand-in music players to choose from, which of them are installed
    /// (the second in a folder inside /Applications), and folder watches the
    /// test fires.
    @MainActor
    private final class Scratch {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let downloads = FileManager.default.temporaryDirectory.appending(path: "AppDelegateTests-\(UUID().uuidString)")
        let notifier = MockUpdateNotifier()
        let first = MockMusicPlayer(bundleID: Players.first, name: "First", failVerifyWith: Denied.automation)
        let second = MockMusicPlayer(bundleID: Players.second, name: "Second", canFade: false, failVerifyWith: Denied.automation)
        lazy var players = MusicPlayerCatalog(players: [first, second], formerDefault: Players.first)
        var installed: Set<String> = [Players.first, Players.second]
        let chooser = FakePlayerChooser()

        private var onFolderChange: (@MainActor () -> Void)?

        func locate(_ bundleID: String) -> URL? {
            guard installed.contains(bundleID) else { return nil }
            let folder = bundleID == Players.second ? "/Applications/Players" : "/Applications"
            return URL(fileURLWithPath: "\(folder)/\(bundleID).app")
        }

        func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> AnyObject? {
            onFolderChange = onChange
            return NSObject()
        }

        func changeFolder() {
            onFolderChange?()
        }

        deinit {
            try? FileManager.default.removeItem(at: downloads)
        }
    }

    /// Every stand-in player refuses control, so a real bootstrap stops at
    /// the permission check, before it would monitor anything.
    private enum Denied {
        static let automation = MusicPlayerError.automationPermissionDenied
    }

    private enum Players {
        static let first = "com.example.first"
        static let second = "com.example.second"
    }

    /// `chosenPlayer`: the player already chosen before this launch, if any.
    /// `realBootstrap`: only for a bootstrap that stops before the player is
    /// scripted.
    @MainActor
    private func makeSUT(
        _ scratch: Scratch = Scratch(),
        chosenPlayer: String? = Players.first,
        realBootstrap: Bool = false,
        updateChecker: UpdateChecker = UpdateChecker { _ in throw URLError(.notConnectedToInternet) },
        updateInstaller: MockUpdateInstaller = MockUpdateInstaller()
    ) -> (AppDelegate, BootstrapCounter) {
        if let chosenPlayer { scratch.preferences.musicPlayer = chosenPlayer }
        let counter = BootstrapCounter()
        let countBootstrap: @MainActor () -> Void = { counter.count += 1 }
        let sut = AppDelegate(
            preferences: scratch.preferences,
            launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
            updateChecker: updateChecker,
            updateInstaller: updateInstaller,
            updateNotifier: scratch.notifier,
            updateDownloadsFolder: scratch.downloads,
            players: scratch.players,
            locateApp: { scratch.locate($0) },
            makePlayerChooser: { _ in scratch.chooser },
            currentVersion: AppVersion("0.2.0"),
            permissionRetryInterval: 0.05,
            retryDelays: 0.02...0.08,
            watchFolder: { scratch.watch($0, onChange: $1) },
            installCheckDelay: .zero,
            bootstrapOverride: realBootstrap ? nil : countBootstrap
        )
        return (sut, counter)
    }

    @MainActor
    @Test("another app's launch does not change health state or re-bootstrap")
    func otherAppLaunchDoesNothing() {
        let (sut, bootstraps) = makeSUT()

        #expect(sut.status.health == .starting)
        sut.handleApplicationDidLaunch(bundleIdentifier: "org.videolan.vlc")
        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("the chosen player's launch sets app back to starting and re-bootstraps")
    func playerLaunchSetsStartingState() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.degraded("First is not running"))

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)

        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("nil bundle identifier does nothing")
    func nilBundleIdentifierDoesNothing() {
        let (sut, bootstraps) = makeSUT()
        sut.setHealth(.ready)

        sut.handleApplicationDidLaunch(bundleIdentifier: nil)

        #expect(sut.status.health == .ready)
        #expect(bootstraps.count == 0)
    }

    // MARK: - Music player

    @MainActor
    @Test("with no player chosen, AutoHush waits for one and offers them all")
    func waitsForPlayer() {
        let (sut, _) = makeSUT(chosenPlayer: nil)
        #expect(sut.player == nil)
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
        #expect(sut.status.statusLine == "Choose a music player")
        #expect(sut.status.playerOptions.map(\.name) == ["First", "Second"])
        #expect(sut.settingsModel.playerOptions == sut.status.playerOptions)
        #expect(sut.settingsModel.chosenPlayerID == nil)
        #expect(sut.currentConfiguration.musicPlayerBundleID == nil)
    }

    @MainActor
    @Test("with no supported player installed, AutoHush says so, and none can be chosen")
    func noPlayerInstalled() {
        let scratch = Scratch()
        scratch.installed = []
        let (sut, bootstraps) = makeSUT(scratch, chosenPlayer: nil)
        #expect(sut.status.health == .needsPlayer("No supported music player is installed"))
        #expect(sut.status.playerOptions.allSatisfy { !$0.isInstalled })

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player == nil)
        #expect(scratch.preferences.musicPlayer == nil)
        #expect(bootstraps.count == 0)

        // Installed later: it can be chosen.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
        sut.chooseMusicPlayer(Players.first)
        #expect(sut.player?.bundleID == Players.first)
    }

    @MainActor
    @Test("choosing a player stores it, shows it and starts over with it; choosing it again does nothing")
    func choosePlayer() {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch, chosenPlayer: nil)

        sut.chooseMusicPlayer(Players.second)
        #expect(scratch.preferences.musicPlayer == Players.second)
        #expect(sut.status.playerName == "Second")
        #expect(!sut.settingsModel.playerCanFade) // its fade settings are dimmed
        #expect(sut.settingsModel.chosenPlayerName == "Second")
        #expect(sut.status.chosenPlayerID == Players.second)
        #expect(sut.settingsModel.chosenPlayerID == Players.second)
        #expect(sut.status.health == .starting)
        #expect(sut.currentConfiguration.musicPlayerBundleID == Players.second)
        #expect(bootstraps.count == 1)

        sut.chooseMusicPlayer(Players.second)
        #expect(bootstraps.count == 1)

        sut.chooseMusicPlayer(Players.first)
        #expect(sut.status.playerName == "First")
        #expect(sut.settingsModel.playerCanFade)
        #expect(sut.currentConfiguration.musicPlayerBundleID == Players.first)
        #expect(bootstraps.count == 2)
    }

    @MainActor
    @Test("a player that isn't installed, or isn't supported, can't be chosen")
    func chooseUnavailablePlayer() {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, bootstraps) = makeSUT(scratch)

        sut.chooseMusicPlayer(Players.second)
        sut.chooseMusicPlayer("com.example.unknown")
        #expect(sut.player?.bundleID == Players.first)
        #expect(scratch.preferences.musicPlayer == Players.first)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("another supported player opening shows it as installed, without starting over")
    func otherPlayerLaunch() {
        let scratch = Scratch()
        scratch.installed = [Players.first]
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.ready)

        scratch.installed.insert(Players.second)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.status.playerOptions.map(\.isInstalled) == [true, true])
        #expect(sut.status.health == .ready)
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("while no player is chosen, a supported player opening brings the welcome window back")
    func playerLaunchWhileWaiting() {
        let (sut, bootstraps) = makeSUT(chosenPlayer: nil)
        #expect(!sut.isShowingPlayerChooser)

        sut.handleApplicationDidLaunch(bundleIdentifier: Players.second)
        #expect(sut.isShowingPlayerChooser)
        #expect(bootstraps.count == 0)

        sut.chooseMusicPlayer(Players.second)
        #expect(!sut.isShowingPlayerChooser)
    }

    @MainActor
    @Test("the chosen player is left out of Settings → Apps and the ignored apps")
    func chosenPlayerNotListedAsApp() {
        let scratch = Scratch()
        let first = AudioSource(id: Players.first, name: "First")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        scratch.preferences.recordSeen([first, vlc])
        scratch.preferences.ignoredApps = [first]
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.status.ignoredApps.isEmpty)

        // Once another player is chosen, it's an app like any other.
        sut.chooseMusicPlayer(Players.second)
        #expect(sut.settingsModel.apps.map(\.id) == [Players.first, "org.videolan.vlc"])
        #expect(sut.status.ignoredApps == [first])
    }

    @MainActor
    @Test("only the chosen player's audio is the music; other players count like any app")
    func onlyChosenPlayerIsProtected() {
        let (sut, _) = makeSUT()
        let configuration = sut.currentConfiguration
        #expect(!configuration.isMediaSource(Players.first))
        #expect(configuration.isMediaSource(Players.second))
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
        #expect(sut.status.health == .needsPlayer("Choose a music player"))
    }

    @MainActor
    @Test("while the player needs a permission, starting is tried again every few seconds")
    func retriesWhilePermissionMissing() async {
        let scratch = Scratch()
        // The real bootstrap stops at the permission check, before monitoring anything.
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.first)
        for _ in 0..<200 where await scratch.first.verifyCallCount < 3 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await scratch.first.verifyCallCount >= 3)
        #expect(sut.status.health == .needsPermission(.automation(player: "First")))
        // Logged as an error once; the repeats are the same problem.
        #expect(sut.loggedStartupProblem == "First: \(MusicPlayerError.automationPermissionDenied.localizedDescription)")
    }

    @MainActor
    @Test("a busy or hung player is asked again by itself, less and less often")
    func retriesWhilePlayerNotResponding() async {
        let scratch = Scratch()
        await scratch.second.setFailVerify(MusicPlayerError.playerNotResponding)
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<200 where await scratch.second.verifyCallCount < 3 { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(await scratch.second.verifyCallCount >= 3)
        #expect(sut.status.health == .retrying("Second is not responding"))
        #expect(sut.status.canRetry) // the menu offers Retry too
    }

    @MainActor
    @Test("a player that isn't running isn't asked again until it opens")
    func noRetryWhilePlayerNotRunning() async {
        let scratch = Scratch()
        await scratch.second.setFailVerify(MusicPlayerError.playerNotRunning)
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(200))
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(sut.status.health == .degraded("Second is not running"))
        #expect(!sut.status.canRetry)
    }

    @MainActor
    @Test("Diagnostics in Settings follows what AutoHush sees")
    func diagnostics() {
        let (sut, _) = makeSUT()
        #expect(sut.settingsModel.diagnostics == nil)
        sut.refreshDiagnostics()
        let diagnostics = sut.settingsModel.diagnostics
        #expect(diagnostics?.apps.isEmpty == true) // nothing is monitored in tests
        #expect(diagnostics?.text.contains("Apps with Sound\nNo foreign audio output currently detected.") == true)
        #expect(diagnostics?.sections.first?.rows.first?.value.hasPrefix("First") == true)
        #expect(diagnostics?.text.contains("Automation for First") == true)
    }

    @Test("the waits between automatic starts double up to a ceiling")
    func retryDelays() {
        #expect((1...6).map { AppDelegate.retryDelay(afterFailedStarts: $0, delays: 5...60) } == [5, 10, 20, 40, 60, 60])
    }

    @MainActor
    @Test("only the chosen player is ever asked for permission to control it, and only once chosen")
    func onlyChosenPlayerIsAsked() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, chosenPlayer: nil, realBootstrap: true)

        // Nothing is asked before a player is chosen, not even when one opens.
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        await Task.yield()
        #expect(await scratch.first.verifyCallCount == 0)
        #expect(await scratch.second.verifyCallCount == 0)

        sut.chooseMusicPlayer(Players.second) // also closes the welcome window
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.health == .needsPermission(.automation(player: "Second")))
        #expect(await scratch.second.verifyCallCount == 1)
        #expect(await scratch.first.verifyCallCount == 0)
    }

    @MainActor
    @Test("a chosen player that was uninstalled is reported as not installed")
    func chosenPlayerUninstalled() async {
        let scratch = Scratch()
        scratch.installed = []
        // The real bootstrap stops at the install check, before scripting the player.
        let (sut, _) = makeSUT(scratch, realBootstrap: true)
        sut.handleApplicationDidLaunch(bundleIdentifier: Players.first)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.health == .degraded("First is not installed"))

        // Installed again: it's controlled afresh as soon as AutoHush notices.
        scratch.installed = [Players.first]
        sut.refreshPlayerOptions()
        for _ in 0..<1000 where sut.status.health != .needsPermission(.automation(player: "First")) {
            await Task.yield()
        }
        #expect(sut.status.health == .needsPermission(.automation(player: "First")))
        #expect(await scratch.first.verifyCallCount == 1)
    }

    @MainActor
    @Test("the chosen player uninstalled while AutoHush runs is noticed without a restart, and put back starts it again")
    func playerUninstalledWhileRunning() async {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.ready)
        sut.apply(.playback(.musicPlaying))

        // Moved to the Trash: its folder changes, and nothing else happens.
        scratch.installed = []
        scratch.changeFolder()
        for _ in 0..<1000 where sut.status.health == .ready { await Task.yield() }
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(sut.status.playback == .unknown)
        #expect(bootstraps.count == 0)

        // Put back: controlled afresh.
        scratch.installed = [Players.first]
        scratch.changeFolder()
        for _ in 0..<1000 where bootstraps.count == 0 { await Task.yield() }
        #expect(sut.status.health == .starting)
        #expect(bootstraps.count == 1)
    }

    @MainActor
    @Test("opening the menu notices a player that was uninstalled while it wasn't running")
    func menuNoticesUninstalledPlayer() {
        let scratch = Scratch()
        let (sut, bootstraps) = makeSUT(scratch)
        sut.setHealth(.degraded("First is not running"))

        scratch.installed = []
        sut.refreshPlayerOptions() // what opening the menu or Settings does
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(sut.status.playerOptions.first { $0.bundleID == Players.first }?.isInstalled == false)

        // Asked again, it stays as it is.
        sut.refreshPlayerOptions()
        #expect(sut.status.health == .degraded("First is not installed"))
        #expect(bootstraps.count == 0)
    }

    @MainActor
    @Test("the Applications folders are watched, and the one holding the chosen player's app")
    func watchesApplicationFolders() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let applicationFolders = Set(PlayerOption.applicationFolders.map(\.path))
        #expect(sut.watchedFolders == applicationFolders)

        sut.chooseMusicPlayer(Players.second) // in a folder inside /Applications
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

    @MainActor
    @Test("a pipeline torn down leaves no playback state behind, so no stale pause is handed over")
    func playbackStateEndsWithPipeline() async {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch, realBootstrap: true)
        sut.apply(.playback(.pausedByMonitor))

        // The other player's start stops at the permission check.
        sut.chooseMusicPlayer(Players.second)
        for _ in 0..<1000 where sut.status.health == .starting { await Task.yield() }
        #expect(sut.status.playback == .unknown)
        #expect(sut.status.detection == .pending)
        #expect(sut.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
        #expect(scratch.preferences.pauseHandedOverAt == nil)
    }

    // MARK: - Auto-pause and ignored apps

    @MainActor
    @Test("toggling auto-pause switches it off and on again, and persists")
    func toggleAutoPause() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .off)
        #expect(scratch.preferences.autoPause == AutoPauseSetting(isEnabled: false))

        sut.toggleAutoPause()
        #expect(sut.status.autoPause == .on)
    }

    @MainActor
    @Test("snoozing turns auto-pause off until the end; toggling ends the snooze")
    func snoozeThenToggle() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let now = Date()

        sut.snooze(.oneHour, now: now)
        guard case .snoozed = sut.status.autoPause else {
            Issue.record("expected snoozed, got \(sut.status.autoPause)")
            return
        }
        #expect(scratch.preferences.autoPause.snoozedUntil == AutoPauseSnooze.oneHour.endDate(from: now))

        sut.toggleAutoPause(now: now)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("an expired snooze is cleared at launch")
    func expiredSnoozeCleared() {
        let scratch = Scratch()
        scratch.preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: Date().addingTimeInterval(-60))
        let (sut, _) = makeSUT(scratch)
        #expect(sut.status.autoPause == .on)
        #expect(scratch.preferences.autoPause.snoozedUntil == nil)
    }

    @MainActor
    @Test("ignoring and un-ignoring an app updates the menu and the preferences")
    func ignoreApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.setIgnored(vlc, true)
        #expect(sut.status.ignoredApps == [AudioSource(id: "org.videolan.vlc", name: "VLC")])
        #expect(scratch.preferences.ignoredApps.map(\.id) == ["org.videolan.vlc"])

        sut.setIgnored(vlc, false)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
    }

    // MARK: - Settings and updates

    @MainActor
    @Test("the Settings model mirrors auto-pause, apps and timings")
    func settingsModelMirrorsState() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")

        sut.snooze(.oneHour)
        #expect(!sut.settingsModel.isAutoPauseOn)
        #expect(sut.settingsModel.autoPauseNote?.hasPrefix("Turned off until") == true)
        sut.setAutoPause(true)
        #expect(sut.settingsModel.isAutoPauseOn && sut.settingsModel.autoPauseNote == nil)

        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.map(\.id) == ["org.videolan.vlc"])
        #expect(sut.settingsModel.apps.first?.isIgnored == true)

        sut.setTimings(TimingSettings(stopGrace: 4))
        #expect(scratch.preferences.timings.stopGrace == 4)
        #expect(sut.settingsModel.timings.stopGrace == 4)
    }

    @MainActor
    @Test("forgetting an ignored app un-ignores it and removes it from the list")
    func forgetApp() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        sut.setIgnored(vlc, true)

        sut.forget(vlc)
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @MainActor
    @Test("resetting the list forgets every app and ignores none")
    func forgetAllApps() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome", bundlePath: "/Applications/Google Chrome.app")
        scratch.preferences.recordSeen([chrome])
        sut.setIgnored(vlc, true)
        #expect(sut.settingsModel.apps.count == 2)

        sut.forgetAllApps()
        #expect(sut.status.ignoredApps.isEmpty)
        #expect(scratch.preferences.ignoredApps.isEmpty)
        #expect(scratch.preferences.seenApps.isEmpty)
        #expect(sut.settingsModel.apps.isEmpty)
    }

    @MainActor
    @Test("with nothing monitored, quitting doesn't wait")
    func quitsAtOnceWithoutPipeline() {
        let (sut, _) = makeSUT()
        #expect(sut.applicationShouldTerminate(NSApplication.shared) == .terminateNow)
    }

    @Test("startup retries only while the player is not ready yet")
    func transientStartupErrors() {
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotResponding))
        #expect(AppDelegate.isTransientStartupError(MusicPlayerError.playerNotRunning))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.automationPermissionDenied))
        #expect(!AppDelegate.isTransientStartupError(MusicPlayerError.playerCommandFailed("OSStatus -50")))
        #expect(!AppDelegate.isTransientStartupError(StubError.failed))
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
    @Test("turning automatic update checks off is saved and shown in Settings")
    func automaticChecksSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.setChecksForUpdatesAutomatically(false)
        #expect(!scratch.preferences.checksForUpdatesAutomatically)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
        #expect(!sut.updates.isCheckDue())
    }

    @MainActor
    @Test("a pause handed over by the AutoHush before is taken over once, and only when recent")
    func pauseHandover() {
        let now = Date()
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        // Handed over after launch, as a copy that quits for this one does.
        scratch.preferences.pauseHandedOverAt = now.addingTimeInterval(-5)
        #expect(sut.takesOverPause(now: now))
        #expect(scratch.preferences.pauseHandedOverAt == nil) // read once
        scratch.preferences.pauseHandedOverAt = now
        #expect(!sut.takesOverPause(now: now)) // only the first monitoring takes one over

        let stale = Scratch()
        stale.preferences.pauseHandedOverAt = now.addingTimeInterval(-(AppDelegate.pauseHandoverMaxAge + 1))
        #expect(!makeSUT(stale).0.takesOverPause(now: now))
        #expect(!makeSUT().0.takesOverPause(now: now))
    }

    @MainActor
    @Test("the update choice is saved and shown in Settings; it starts at installing")
    func automaticUpdatesSetting() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(sut.settingsModel.updateInstallNote == nil)
        sut.setAutomaticUpdates(.install)
        #expect(scratch.notifier.permissionRequests == 0)
        sut.setAutomaticUpdates(.download)
        #expect(scratch.preferences.automaticUpdates == .download)
        #expect(sut.settingsModel.automaticUpdates == .download)
        #expect(sut.updates.mode == .download)
        #expect(scratch.notifier.permissionRequests == 1) // a choice that notifies asks, if not answered yet
    }

    @MainActor
    @Test("when notifications go off, Settings shows the choice moved to installing, with checks off")
    func notificationsOffShownInSettings() {
        let scratch = Scratch()
        let (sut, _) = makeSUT(scratch)
        sut.setAutomaticUpdates(.download)
        #expect(sut.updates.adapt(toNotificationsOff: true))
        #expect(sut.settingsModel.automaticUpdates == .install)
        #expect(!sut.settingsModel.checksForUpdatesAutomatically)
        #expect(scratch.preferences.automaticUpdates == .install)
        #expect(!scratch.preferences.checksForUpdatesAutomatically)
    }

    @MainActor
    @Test("Settings says why AutoHush can't update itself")
    func installUnavailableNote() {
        let (sut, _) = makeSUT(updateInstaller: MockUpdateInstaller(unavailability: .readOnlyLocation))
        #expect(sut.settingsModel.updateInstallNote == "AutoHush can't update itself, because it can't write to the folder it's in.")
    }
}
