import AppKit
import Observation
import Testing
@testable import AutoHushApp
@testable import AutoHushKit
import AutoHushTestSupport

@Suite("SettingsModel")
@MainActor
struct SettingsModelTests {
    /// What Settings asked of AppDelegate and the updates; the user's
    /// settings show their own changes.
    private let log = CallLog()
    private let actions: FakeAppActions
    private let updates: FakeUpdateCommands

    init() {
        actions = FakeAppActions(log: log)
        updates = FakeUpdateCommands(log: log)
    }

    private func makeModel(_ controller: MockLaunchAtLoginController,
                           settings: UserSettings = .inMemory()) -> SettingsModel {
        SettingsModel(settings: settings, updates: updates, actions: actions, launchAtLoginController: controller)
    }

    /// The apps as the app's state has them.
    private func show(_ model: SettingsModel, seen: [AudioSource], ignored: [AudioSource]) {
        model.state.status.seenApps = seen
        model.state.status.ignoredApps = ignored
    }

    @Test("the version shows with its build number for About and Diagnostics, alone without one, and not at all while unknown")
    func fullVersion() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.fullVersion == nil && model.fullVersion(build: "19") == nil)
        updates.currentVersion = AppVersion("1.2.3")
        #expect(model.fullVersion(build: "19") == "1.2.3 (19)")
        #expect(model.fullVersion(build: nil) == "1.2.3")
        #expect(model.fullVersion?.hasPrefix("1.2.3") == true) // this copy's build, whichever it is
    }

    @Test("a login item macOS waits to have allowed shows as such, followed when refreshed")
    func loginItemNeedsApproval() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        let model = makeModel(controller)
        #expect(!model.launchAtLoginNeedsApproval)
        controller.needsApproval = true
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLoginNeedsApproval)
    }

    @Test("AntiDot mode is the way past Audio Recording; Back returns to the welcome window's players")
    func permissionActions() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.useAntiDotMode()
        #expect(model.detectionMethod == .playbackSignals)
        #expect(model.settings.state.detection == .playbackSignals)
        model.welcomeAsksPermissions = true
        model.showWelcomePlayers()
        #expect(!model.welcomeAsksPermissions)
    }

    @Test("AntiDot mode can't be turned on while the player can only be muted: its switch is off, saying why")
    func antiDotUnavailable() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        var muted = PlayerOption(bundleID: "com.example.muted", name: "Muted", appURL: URL(fileURLWithPath: "/Applications/Muted.app"),
                                 kind: .checkedApp)
        muted.pausesByMuting = true
        muted.needsAudioLevels = true
        model.state.status.playerOptions = [muted]
        #expect(model.antiDotUnavailableFor == nil) // not the player
        model.state.status.chosenPlayerID = muted.bundleID
        #expect(model.antiDotUnavailableFor == "Muted")
        model.setAntiDotMode(true)
        model.useAntiDotMode()
        #expect(!model.isAntiDotMode)
        #expect(DetectionSettingsView.unavailableNote("Muted") == "AutoHush can only mute Muted, and muting needs Audio Recording, which AntiDot mode doesn’t use.")
    }

    @Test("the chosen player's traits come from its option, followed: checked again to be muted (the same app), AntiDot mode's switch is off at once; its fades too")
    func chosenPlayerTraitsFollowed() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Radio")
        #expect(model.antiDotUnavailableFor == nil && model.playerCanFade && !model.state.status.playerMutes)

        let antiDot = Locked(0) // how many times what it follows changed (`withObservationTracking`)
        withObservationTracking { _ = model.antiDotUnavailableFor } onChange: { antiDot.increment() }
        model.state.status.playerOptions[0].needsAudioLevels = true
        #expect(antiDot.value == 1)
        model.state.status.playerOptions[0].pausesByMuting = true
        #expect(model.antiDotUnavailableFor == "Radio")
        #expect(model.state.status.playerMutes && model.state.status.playerNeedsLevels)

        let fades = Locked(0)
        withObservationTracking { _ = model.playerCanFade } onChange: { fades.increment() }
        model.state.status.playerOptions[0].canFade = false
        #expect(fades.value == 1)
        #expect(!model.playerCanFade)
    }

    @Test("a switch that can't be changed shows off, whatever is saved, and shows the saved value again once it can")
    func unavailableSwitchShowsOff() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(fadesEnabled: true, levelsMusic: true))
        #expect(SettingsSwitch.fades.isOn(model) && SettingsSwitch.levelsMusic.isOn(model))
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.playerOptions[0].canFade = false
        model.setAntiDotMode(true)
        #expect(SettingsSwitch.fades.isUnavailable(model) && !SettingsSwitch.fades.isOn(model))
        #expect(SettingsSwitch.levelsMusic.isUnavailable(model) && !SettingsSwitch.levelsMusic.isOn(model))
        #expect(model.timings.fadesEnabled && model.timings.levelsMusic) // kept
        model.state.status.playerOptions[0].canFade = true
        model.setAntiDotMode(false)
        #expect(SettingsSwitch.fades.isOn(model) && SettingsSwitch.levelsMusic.isOn(model))
    }

    @Test("reflects the login item's state")
    func reflectsLaunchAtLogin() {
        #expect(makeModel(MockLaunchAtLoginController(isEnabled: true)).launchAtLoginEnabled)
        #expect(!makeModel(MockLaunchAtLoginController(isEnabled: false)).launchAtLoginEnabled)
    }

    @Test("turning launch at login on registers the login item")
    func enableLaunchAtLogin() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        let model = makeModel(controller)
        model.setLaunchAtLogin(true)
        #expect(controller.setEnabledCalls == [true])
        #expect(model.launchAtLoginEnabled)
        #expect(model.launchAtLoginError == nil)
    }

    @Test("a failed change keeps the real state and shows the error inline")
    func failedLaunchAtLogin() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        controller.setEnabledResult = .failure(StubError.failed)
        let model = makeModel(controller)
        model.setLaunchAtLogin(true)
        #expect(!model.launchAtLoginEnabled)
        #expect(model.launchAtLoginError == "Couldn’t change the login item: stub failed")

        controller.setEnabledResult = .success(())
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError == nil)
    }

    @Test("opening Login Items settings is delegated")
    func openLoginItems() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        makeModel(controller).openLoginItemsSettings()
        #expect(controller.openSystemSettingsCallCount == 1)
    }

    @Test("what the menu shows too comes from the app's state, and follows it")
    func readsTheAppState() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let spotify = PlayerOption(bundleID: "com.spotify.client", name: "Spotify",
                                   appURL: URL(fileURLWithPath: "/Applications/Spotify.app"), kind: .app)
        model.state.status.playerOptions = [spotify]
        model.state.status.chosenPlayerID = spotify.bundleID
        #expect(model.playerOptions == [spotify])
        #expect(model.chosenPlayerID == spotify.bundleID && model.chosenPlayerName == "Spotify")
        #expect(!model.canLearnControlsAgain)

        model.state.status.setHealth(.needsPermission(.automation(player: "Spotify")))
        #expect(!model.statusLine.isEmpty && model.statusLine == model.state.status.statusLine)
        #expect(model.statusNeedsAttention)

        model.state.status.autoPause = .snoozed("until 15:30")
        #expect(!model.isAutoPauseOn)
        #expect(model.autoPauseNote == "Turned off until 15:30.")

        model.state.status.learning = .learned
        #expect(model.learning == .learned && model.canLearnControlsAgain)
    }

    @Test("in AntiDot mode, Settings and the welcome window offer an app that can only be muted as one that can't be chosen")
    func offeredPlayersInAntiDotMode() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        var muted = PlayerOption(bundleID: "com.example.muted", name: "Muted", appURL: URL(fileURLWithPath: "/Applications/Muted.app"),
                                 kind: .checkedApp)
        muted.pausesByMuting = true
        muted.needsAudioLevels = true
        let spotify = PlayerOption(bundleID: "com.spotify.client", name: "Spotify",
                                   appURL: URL(fileURLWithPath: "/Applications/Spotify.app"), kind: .app)
        model.state.status.playerOptions = [muted, spotify]
        #expect(model.offeredPlayers.map(\.name) == ["Spotify", "Muted"])
        #expect(model.offeredPlayers.map(\.isClickable) == [true, true])

        model.setAntiDotMode(true)
        #expect(model.offeredPlayers.map(\.isClickable) == [true, false])
        #expect(model.playerOptions == [muted, spotify]) // as the app's state has them
    }

    @Test("the player card offers Reopen and Unmute as the menu's card does, following the status as it changes")
    func reopenAndUnmute() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Jukebox")
        model.state.status.setHealth(.ready)
        model.state.status.playback = .musicPlaying
        #expect(!model.offersReopenPlayer && !model.offersUnmute)

        let reopen = Locked(0)
        withObservationTracking { _ = model.offersReopenPlayer } onChange: { reopen.increment() }
        model.state.status.playerNeedsReopen = true
        #expect(reopen.value == 1)
        #expect(model.offersReopenPlayer)
        model.state.status.playerNeedsReopen = false

        let unmute = Locked(0)
        withObservationTracking { _ = model.offersUnmute } onChange: { unmute.increment() }
        model.state.status.playerOptions[0].pausesByMuting = true
        model.state.status.setActiveSources([AudioSource(id: "com.apple.Safari", name: "Safari")])
        model.state.status.playback = .pausedByMonitor
        #expect(unmute.value == 1)
        #expect(model.offersUnmute && !model.offersReopenPlayer)
        model.state.status.playback = .musicPlaying
        #expect(!model.offersUnmute)
    }

    @Test("a window follows only the parts it shows: the music's state leaves the apps alone, the apps leave the status line alone; the apps are ordered again as their order changes")
    func followsPartByPart() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        show(model, seen: [vlc], ignored: [])
        model.state.status.setHealth(.ready)

        let apps = Locked(0)
        withObservationTracking { _ = model.appList.apps } onChange: { apps.increment() }
        model.state.status.playback = .pausedByMonitor
        model.state.status.setActiveSources([chrome])
        #expect(apps.value == 0)

        let line = Locked(0)
        withObservationTracking { _ = model.statusLine } onChange: { line.increment() }
        show(model, seen: [vlc, chrome], ignored: [vlc])
        #expect(line.value == 0)
        #expect(apps.value == 1)
        #expect(model.appList.apps.map(\.id) == [vlc.id, chrome.id])
        model.state.status.playback = .musicPlaying
        #expect(line.value == 1)

        let order = Locked(0)
        withObservationTracking { _ = model.appList.apps } onChange: { order.increment() }
        model.appList.setOrder(AppListOrder(criterion: .name))
        #expect(order.value == 1)
        #expect(model.appList.apps.map(\.id) == [chrome.id, vlc.id])
    }

    @Test("Settings' own setters store through the user's settings, the timings clamped first")
    func storesThroughUserSettings() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(startConfirmation: 99))
        model.setDetectionMethod(.openStreams)
        #expect(model.timings.startConfirmation == 5)
        #expect(model.settings.state.timings.startConfirmation == 5)
        #expect(model.detectionMethod == .openStreams)
        #expect(model.settings.state.detection == .openStreams)
        #expect(log.calls.isEmpty)
    }

    @Test("AntiDot mode switches between audio levels and playback signals; each way's summary says the engine's least start")
    func antiDotMode() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(!model.isAntiDotMode)

        model.setAntiDotMode(true)
        #expect(model.isAntiDotMode && model.detectionMethod == .playbackSignals)
        model.setDetectionMethod(.openStreams)
        model.setAntiDotMode(true) // already on: keeps the chosen method
        #expect(model.detectionMethod == .openStreams)
        model.setAntiDotMode(false)
        #expect(!model.isAntiDotMode && model.detectionMethod == .audioLevels)
        #expect(model.settings.state.detection == .audioLevels)
        // How long an app must play before your player pauses, at the least.
        let configuration = AppConfiguration()
        #expect(DetectionMethod.playbackSignals.summary.contains("at least \(Int(configuration.minimumStartWithoutVideo)) seconds"))
        #expect(DetectionMethod.openStreams.summary.contains("at least \(Int(configuration.minimumStartWithOpenStreams)) seconds"))
    }

    @Test("each page's Restore Defaults restores the settings it shows only: Detection's timings, the fades, or Advanced's switches")
    func restoreDefaults() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let changed = TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                     fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false,
                                     levelsMusic: true, staysPausedAfterCalls: true)
        model.setTimings(changed)
        #expect(!model.detectionTimingsAreDefaults && !model.fadesAreDefaults && !model.advancedAreDefaults)

        model.restoreDefaultDetectionTimings()
        #expect(model.detectionTimingsAreDefaults)
        #expect(!model.fadesAreDefaults) // the other pages keep their own
        #expect(model.timings == TimingSettings(fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false,
                                                levelsMusic: true, staysPausedAfterCalls: true))

        model.setTimings(changed)
        model.restoreDefaultFades()
        #expect(model.fadesAreDefaults)
        #expect(!model.detectionTimingsAreDefaults)
        #expect(model.timings == TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                                levelsMusic: true, staysPausedAfterCalls: true))

        model.setTimings(changed)
        model.restoreDefaultAdvanced()
        #expect(model.advancedAreDefaults)
        #expect(model.timings == TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                                fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false))

        // In AntiDot mode the silence threshold is greyed out: it neither lights
        // Restore Defaults nor is restored.
        model.setTimings(TimingSettings(silenceThresholdDB: -40))
        #expect(!model.detectionTimingsAreDefaults)
        model.setAntiDotMode(true)
        #expect(model.detectionTimingsAreDefaults)
        model.setTimings(TimingSettings(startConfirmation: 2, silenceThresholdDB: -40))
        model.restoreDefaultDetectionTimings()
        #expect(model.timings == TimingSettings(silenceThresholdDB: -40))
    }

    // MARK: - Updates

    @Test("beside Check Now: the version until a check, then what it found; under it, when the last one was")
    func updateRow() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.updateTitle == "AutoHush")
        updates.currentVersion = AppVersion("0.3.11")
        #expect(model.updateTitle == "AutoHush 0.3.11")
        #expect(model.lastCheckedNote() == nil)

        let now = Date()
        updates.lastCheck = now.addingTimeInterval(-2 * 3600)
        updates.status = "AutoHush 0.3.11 is up to date."
        #expect(model.updateTitle == "AutoHush 0.3.11 is up to date.")
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: now.addingTimeInterval(-2 * 3600), relativeTo: now)
        #expect(model.lastCheckedNote(now: now) == "Last checked \(when)")
    }

    @Test("the update rows read the updates themselves, and follow them as they change (notifications turned off, a check's status and when it ran, the settings), with no one passing them on; the install note as at launch")
    func updateRowsFollowTheUpdates() async {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let notifier = MockUpdateNotifier()
        let folder = TemporaryFolder("SettingsModelTests", create: false)
        let updates = UpdateController(
            system: UpdateController.System(checker: .latestRelease("v0.3.0"), installer: MockUpdateInstaller(unavailability: .readOnlyLocation),
                                            notifier: notifier, downloadsFolder: folder.url, currentVersion: AppVersion("0.2.0")),
            preferences: preferences, isQuietMoment: { false }, quit: {}, onOffer: { _ in }
        )
        let model = SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
        #expect(model.currentVersion == "0.2.0" && model.updateStatus == nil && model.lastUpdateCheck == nil)
        #expect(model.updateInstallNote == UpdateInstallUnavailability.readOnlyLocation.explanation)

        /// Whether what `read` reads is told of `change`, as a view drawn from it is.
        func follows(_ read: () -> Void, after change: () async -> Void) async -> Bool {
            let changed = Locked(false)
            withObservationTracking(read) { changed.value = true }
            await change()
            return changed.value
        }
        notifier.currentPermission = .off
        #expect(await follows({ _ = model.notificationsOff }, after: { await updates.followNotificationPermission() }))
        #expect(model.notificationsOff)
        #expect(await follows({ _ = model.updateStatus }, after: { await updates.check(userInitiated: false) }))
        #expect(model.updateStatus == "Version 0.3.0 is available." && model.lastUpdateCheck == preferences.lastUpdateCheck)
        #expect(await follows({ _ = model.automaticUpdates }, after: { updates.setMode(.notify) }))
        #expect(model.automaticUpdates == .notify)
        #expect(await follows({ _ = model.checksForUpdatesAutomatically }, after: { updates.setChecksAutomatically(false) }))
        #expect(!model.checksForUpdatesAutomatically)
    }

    @Test("the menu says why a switch can't be changed as a fragment, without a period; nothing while it can")
    func unavailableReasons() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(SettingsSwitch.allCases.allSatisfy { $0.unavailableReason(model) == nil })
        model.setAntiDotMode(true)
        #expect(SettingsSwitch.levelsMusic.unavailableReason(model) == "Off in AntiDot mode")
    }
}
