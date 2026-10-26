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

    @Test("keeping the menu bar icon beside the system's icons moves it there at once; letting it go doesn't move it")
    func menuBarIconKept() {
        let defaults = UserDefaults(suiteName: "SettingsModelTests-\(UUID().uuidString)")!
        let model = SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                                  menuBarIcon: MenuBarIconPlace(defaults: defaults))
        #expect(!model.keepsMenuBarIconNearSystemIcons)
        model.setKeepsMenuBarIconNearSystemIcons(true)
        #expect(model.keepsMenuBarIconNearSystemIcons && MenuBarIconPlace(defaults: defaults).keepsNearSystemIcons)
        #expect(log.calls == ["moveMenuBarIcon"])
        model.setKeepsMenuBarIconNearSystemIcons(false)
        #expect(!MenuBarIconPlace(defaults: defaults).keepsNearSystemIcons)
        #expect(log.calls == ["moveMenuBarIcon"])
    }

    @Test("General says the menu bar icon is hidden as it's read again (Settings opening), and no longer once it was moved beside the system's icons")
    func menuBarIconHidden() {
        let defaults = UserDefaults(suiteName: "SettingsModelTests-\(UUID().uuidString)")!
        let model = SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false),
                                  menuBarIcon: MenuBarIconPlace(defaults: defaults))
        #expect(!model.menuBarIconHidden)
        actions.menuBarIconIsHidden = true // behind the notch
        #expect(!model.menuBarIconHidden) // not read yet
        model.refreshMenuBarIcon()
        #expect(model.menuBarIconHidden)
        model.setKeepsMenuBarIconNearSystemIcons(true) // moved: it shows
        #expect(!model.menuBarIconHidden)
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

    @Test("AntiDot mode keeps its way: turned off and on again, or used past Audio Recording, it's the way chosen last")
    func antiDotKeepsItsWay() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setAntiDotMode(true)
        #expect(model.detectionMethod == .playbackSignals) // none chosen yet
        model.setDetectionMethod(.openStreams)
        model.setAntiDotMode(false)
        #expect(model.detectionMethod == .audioLevels)
        model.setAntiDotMode(true)
        #expect(model.detectionMethod == .openStreams)
        model.setAntiDotMode(false)
        model.useAntiDotMode()
        #expect(model.detectionMethod == .openStreams)
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
        #expect(DetectionText.unavailableNote("Muted") == "AutoHush can only mute Muted, and muting needs Audio Recording, which AntiDot mode doesn’t use.")
    }

    @Test("the chosen player's traits come from its option")
    func chosenPlayerTraits() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Radio")
        #expect(model.antiDotUnavailableFor == nil && model.playerCanFade && !model.state.status.playerMutes)
    }

    @Test("Sound Sources' apps say “Mutes your player” while the chosen player is muted in place of the pause")
    func playerMutesNow() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Radio")
        model.state.status.playback = .pausedByMonitor
        #expect(!model.playerMutesNow)
        model.state.status.playerMutedInstead = true
        #expect(model.playerMutesNow)
    }

    @Test("the chosen player checked again to be muted (the same app) has AntiDot mode's switch off at once")
    func chosenPlayerTraitsFollowed() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Radio")
        let antiDot = Locked(0) // how many times what it follows changed (`withObservationTracking`)
        withObservationTracking { _ = model.antiDotUnavailableFor } onChange: { antiDot.increment() }
        model.state.status.playerOptions[0].needsAudioLevels = true
        #expect(antiDot.value == 1)
        model.state.status.playerOptions[0].pausesByMuting = true
        #expect(model.antiDotUnavailableFor == "Radio")
        #expect(model.state.status.playerMutes && model.state.status.playerNeedsLevels)
    }

    @Test("the chosen player's fades follow its option")
    func chosenPlayerFadesFollowed() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.state.status.choosePlayer(named: "Radio")
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

    @Test("with Resume playback off, leveling and Stay paused after calls are dimmed, saying why; the latter still shows its own value")
    func resumeOffDimsResumeSettings() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(resumesPlayback: false, levelsMusic: true, staysPausedAfterCalls: true))
        #expect(SettingsSwitch.levelsMusic.isUnavailable(model) && !SettingsSwitch.levelsMusic.isOn(model))
        #expect(SettingsSwitch.levelsMusic.unavailableReason(model) == SettingsSwitch.resumeOffNote)
        #expect(SettingsSwitch.staysPausedAfterCalls.isUnavailable(model) && SettingsSwitch.staysPausedAfterCalls.isOn(model))
        #expect(SettingsSwitch.staysPausedAfterCalls.unavailableReason(model) == SettingsSwitch.resumeOffNote)
        #expect(!SettingsSwitch.resumesPlayback.isOn(model) && !SettingsSwitch.resumesPlayback.isUnavailable(model))
        model.setAntiDotMode(true) // AntiDot mode's reason first
        #expect(SettingsSwitch.levelsMusic.unavailableReason(model) == AntiDotText.featureOff)
        model.setAntiDotMode(false)
        SettingsSwitch.resumesPlayback.set(true, in: model)
        #expect(model.timings.resumesPlayback && SettingsSwitch.levelsMusic.isOn(model))
        #expect(!SettingsSwitch.staysPausedAfterCalls.isUnavailable(model))
        #expect(SettingsSwitch.staysPausedAfterCalls.unavailableReason(model) == nil)
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

    @Test("the error of a failed change goes once the login item is changed elsewhere (System Settings), not before")
    func launchAtLoginErrorClears() {
        let controller = MockLaunchAtLoginController(isEnabled: false)
        controller.setEnabledResult = .failure(StubError.failed)
        let model = makeModel(controller)
        model.setLaunchAtLogin(true)
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLoginError != nil) // nothing changed yet
        controller.isEnabled = true // turned on in System Settings
        model.refreshLaunchAtLogin()
        #expect(model.launchAtLoginEnabled && model.launchAtLoginError == nil)

        // Only approved meanwhile (it was on, waiting for approval): the error goes too.
        controller.needsApproval = true
        model.refreshLaunchAtLogin()
        model.setLaunchAtLogin(true)
        #expect(model.launchAtLoginError != nil)
        controller.needsApproval = false
        model.refreshLaunchAtLogin()
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

    private let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
    private let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")

    /// Settings' model with VLC among the apps, the player ready, and the
    /// music paused for Chrome if `paused`.
    private func showingVLC(paused: Bool) -> SettingsModel {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        show(model, seen: [vlc], ignored: [])
        model.state.status.setHealth(.ready)
        if paused {
            model.state.status.playback = .pausedByMonitor
            model.state.status.setActiveSources([chrome])
        }
        return model
    }

    @Test("a window showing the apps isn't told of the music's state")
    func followsPartByPart() {
        let model = showingVLC(paused: false)
        let apps = Locked(0)
        withObservationTracking { _ = model.appList.apps } onChange: { apps.increment() }
        model.state.status.playback = .pausedByMonitor
        model.state.status.setActiveSources([chrome])
        #expect(apps.value == 0)
    }

    @Test("a window showing the status line isn't told of the apps, only of the music's state")
    func statusLineLeavesTheApps() {
        let model = showingVLC(paused: true)
        let line = Locked(0)
        withObservationTracking { _ = model.statusLine } onChange: { line.increment() }
        show(model, seen: [vlc, chrome], ignored: [vlc])
        #expect(line.value == 0)
        model.state.status.playback = .musicPlaying
        #expect(line.value == 1)
    }

    @Test("a window showing the apps is told as they change")
    func appsFollowed() {
        let model = showingVLC(paused: true)
        let apps = Locked(0)
        withObservationTracking { _ = model.appList.apps } onChange: { apps.increment() }
        show(model, seen: [vlc, chrome], ignored: [vlc])
        #expect(apps.value == 1)
        #expect(model.appList.apps.map(\.id) == [vlc.id, chrome.id])
    }

    @Test("the apps are ordered again as their order changes")
    func appsOrderedAgain() {
        let model = showingVLC(paused: true)
        show(model, seen: [vlc, chrome], ignored: [vlc])
        model.state.status.playback = .musicPlaying
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
        #expect(DetectionMethod.playbackSignals.summary.contains("under \(Int(configuration.minimumStartWithoutVideo)) seconds"))
        #expect(DetectionMethod.openStreams.summary.contains("stay open \(Int(configuration.minimumStartWithOpenStreams)) seconds"))
    }

    @Test("each card's Restore Defaults restores the settings it shows only: Behavior's its switches, Fine-Tuning's its sliders and ways")
    func restoreDefaults() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let changed = TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                     fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false,
                                     pausesOnOutputDisconnect: true,
                                     levelsMusic: true, levelingMaxCutDB: 14, levelingMinCutDB: 5,
                                     pausesForMicrophone: true, staysPausedAfterCalls: true)
        model.setTimings(changed)
        #expect(!model.isDefault(.pausing) && !model.isDefault(.resuming) && !model.isDefault(.fades) && !model.isDefault(.volume))
        #expect(!model.isDefault(.timing) && !model.isDefault(.volumeLimits) && !model.isDefault(.detection))
        #expect(model.isDefault(.fadeLengths)) // greyed out: the fades are off

        // Behavior's cards: their switches only.
        model.restoreDefaults(.pausing)
        var expected = changed
        expected.pausesForMicrophone = false
        expected.pausesOnOutputDisconnect = false
        #expect(model.timings == expected && model.isDefault(.pausing) && !model.isDefault(.timing))

        model.setTimings(changed)
        model.restoreDefaults(.resuming)
        expected = changed
        expected.staysPausedAfterCalls = false
        #expect(model.timings == expected && model.isDefault(.resuming))

        model.setTimings(changed)
        model.restoreDefaults(.fades)
        expected = changed
        expected.fadesEnabled = true
        #expect(model.timings == expected && model.isDefault(.fades) && !model.isDefault(.fadeLengths))

        model.setTimings(changed)
        model.restoreDefaults(.volume)
        expected = changed
        expected.levelsMusic = false
        #expect(model.timings == expected && model.isDefault(.volume) && model.isDefault(.volumeLimits)) // the limits greyed out now

        // Fine-Tuning's cards: their sliders only.
        model.setTimings(changed)
        model.restoreDefaults(.timing)
        expected = changed
        expected.startConfirmation = TimingSettings.defaults.startConfirmation
        expected.stopGrace = TimingSettings.defaults.stopGrace
        #expect(model.timings == expected && model.isDefault(.timing) && !model.isDefault(.pausing))

        var fading = changed
        fading.fadesEnabled = true
        model.setTimings(fading)
        model.restoreDefaults(.fadeLengths)
        expected = fading
        expected.fadeOutDuration = TimingSettings.defaults.fadeOutDuration
        expected.fadeInDuration = TimingSettings.defaults.fadeInDuration
        #expect(model.timings == expected && model.isDefault(.fadeLengths))

        model.setTimings(changed)
        model.restoreDefaults(.volumeLimits)
        expected = changed
        expected.levelingMaxCutDB = TimingSettings.defaults.levelingMaxCutDB
        expected.levelingMinCutDB = TimingSettings.defaults.levelingMinCutDB
        #expect(model.timings == expected && model.isDefault(.volumeLimits) && !model.isDefault(.volume))

        model.setTimings(changed)
        model.restoreDefaults(.detection)
        expected = changed
        expected.silenceThresholdDB = TimingSettings.defaults.silenceThresholdDB
        #expect(model.timings == expected && model.isDefault(.detection))
    }

    @Test("a Behavior row opens Fine-Tuning at its card, the highlight with it when pressed by a key")
    func showFineTuning() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.showFineTuning(.volumeLimits)
        #expect(model.fineTuningFocus == .volumeLimits && log.calls.last == "fineTuning" && !model.fineTuningFocusTakesHighlight)
        model.showFineTuning(.detection, byKeyboard: true) // Return on the row: the highlight goes there too
        #expect(model.fineTuningFocus == .detection && model.fineTuningFocusTakesHighlight)
    }

    @Test("greyed out, a Fine-Tuning setting is left as it is: the fade lengths while the fades are off, the fade-in and the wait to resume while nothing resumes, the threshold in AntiDot mode, where Detection restores the way")
    func fineTuningRestoresWhatShows() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                        fadeOutDuration: 3, fadesEnabled: false, resumesPlayback: false))
        model.restoreDefaults(.fadeLengths)
        #expect(model.timings.fadeOutDuration == 3)
        #expect(model.isDefault(.timing) == false)
        model.restoreDefaults(.timing)
        #expect(model.timings.startConfirmation == TimingSettings.defaults.startConfirmation && model.timings.stopGrace == 7)
        #expect(model.isDefault(.timing))

        // The fades on, nothing resuming: the fade-in is greyed out alone.
        model.setTimings(TimingSettings(startConfirmation: model.timings.startConfirmation, stopGrace: 7, silenceThresholdDB: -40,
                                        fadeInDuration: 4, fadesEnabled: true, resumesPlayback: false))
        #expect(model.isDefault(.fadeLengths))
        model.setTimings(TimingSettings(startConfirmation: model.timings.startConfirmation, stopGrace: 7, silenceThresholdDB: -40,
                                        fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: true, resumesPlayback: false))
        #expect(!model.isDefault(.fadeLengths))
        model.restoreDefaults(.fadeLengths)
        #expect(model.timings.fadeOutDuration == TimingSettings.defaults.fadeOutDuration && model.timings.fadeInDuration == 4)
        #expect(model.isDefault(.fadeLengths))

        model.setAntiDotMode(true)
        model.setDetectionMethod(.openStreams)
        #expect(!model.isDefault(.detection))
        model.restoreDefaults(.detection)
        #expect(model.detectionMethod == .playbackSignals && model.timings.silenceThresholdDB == -40 && model.isDefault(.detection))
    }

    @Test("Modes' Restore Defaults turns AntiDot mode off; Startup and Menu Bar's turns launch at login off and leaves the icon where it is; Updates' checks daily and installs")
    func restoreDefaultsOfTheOtherCards() {
        let icon = MenuBarIconPlace(defaults: UserDefaults(suiteName: "restore-\(UUID())")!)
        let model = SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                                  launchAtLoginController: MockLaunchAtLoginController(isEnabled: false), menuBarIcon: icon)
        #expect(model.isDefault(.modes) && model.isDefault(.startup) && model.isDefault(.updates))

        model.setAntiDotMode(true)
        #expect(!model.isDefault(.modes))
        model.restoreDefaults(.modes)
        #expect(!model.isAntiDotMode && model.isDefault(.modes))

        model.setLaunchAtLogin(true)
        model.setKeepsMenuBarIconNearSystemIcons(true)
        #expect(!model.isDefault(.startup))
        model.restoreDefaults(.startup)
        #expect(!model.launchAtLoginEnabled && !model.keepsMenuBarIconNearSystemIcons && model.isDefault(.startup))

        updates.checksAutomatically = false
        updates.mode = .notify
        #expect(!model.isDefault(.updates))
        model.restoreDefaults(.updates)
        #expect(updates.log.calls.suffix(2) == ["autoUpdate true", "updates install"])
    }

    @Test("a card greyed out has nothing for Restore Defaults to change: the fades with a player AutoHush can't fade, Volume in AntiDot mode or with Resume playback off")
    func restoreDefaultsWhileDimmed() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        model.setTimings(TimingSettings(fadesEnabled: false, levelsMusic: true))
        model.state.status.choosePlayer(named: "Radio")
        #expect(!model.isDefault(.fades) && !model.isDefault(.volume))
        model.state.status.playerOptions[0].canFade = false
        #expect(model.isDefault(.fades))
        model.setAntiDotMode(true)
        #expect(model.isDefault(.volume))
        model.setAntiDotMode(false)
        #expect(!model.isDefault(.volume))
        model.setTimings(TimingSettings(fadesEnabled: false, resumesPlayback: false, levelsMusic: true))
        #expect(model.isDefault(.volume))
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

    /// Settings' model on real updates, which find v0.3.0 and can't install
    /// it (AutoHush's folder is read-only).
    private func updateRows() -> (model: SettingsModel, updates: UpdateController, notifier: MockUpdateNotifier,
                                  preferences: Preferences, folder: TemporaryFolder) {
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
        return (model, updates, notifier, preferences, folder)
    }

    /// Whether what `read` reads is told of `change`, as a view drawn from it is.
    private func follows(_ read: () -> Void, after change: () async -> Void) async -> Bool {
        let changed = Locked(false)
        withObservationTracking(read) { changed.value = true }
        await change()
        return changed.value
    }

    @Test("the update rows read the updates themselves, with no one passing them on: the version, and no check yet")
    func updateRowsReadTheUpdates() {
        let bench = updateRows()
        #expect(bench.model.currentVersion == "0.2.0" && bench.model.updateStatus == nil && bench.model.lastUpdateCheck == nil)
    }

    @Test("the update rows' install note is as at launch")
    func updateRowsInstallNote() {
        let bench = updateRows()
        #expect(bench.model.updateInstallNote == UpdateInstallUnavailability.readOnlyLocation.explanation)
    }

    @Test("the update rows follow notifications turned off")
    func updateRowsFollowNotifications() async {
        let bench = updateRows()
        bench.notifier.currentPermission = .off
        #expect(await follows({ _ = bench.model.notificationsOff }, after: { await bench.updates.followNotificationPermission() }))
        #expect(bench.model.notificationsOff)
    }

    @Test("the update rows follow a check's status and when it ran")
    func updateRowsFollowTheCheck() async {
        let bench = updateRows()
        #expect(await follows({ _ = bench.model.updateStatus }, after: { await bench.updates.check(userInitiated: false) }))
        #expect(bench.model.updateStatus == "Version 0.3.0 is available." && bench.model.lastUpdateCheck == bench.preferences.lastUpdateCheck)
    }

    @Test("the update rows follow the update settings")
    func updateRowsFollowTheSettings() async {
        let bench = updateRows()
        #expect(await follows({ _ = bench.model.automaticUpdates }, after: { bench.updates.setMode(.notify) }))
        #expect(bench.model.automaticUpdates == .notify)
        #expect(await follows({ _ = bench.model.checksForUpdatesAutomatically }, after: { bench.updates.setChecksAutomatically(false) }))
        #expect(!bench.model.checksForUpdatesAutomatically)
    }

    @Test("the menu says why a switch can't be changed as a fragment, without a period; nothing while it can")
    func unavailableReasons() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(SettingsSwitch.allCases.allSatisfy { $0.unavailableReason(model) == nil })
        model.setAntiDotMode(true)
        #expect(SettingsSwitch.levelsMusic.unavailableReason(model) == "Off in AntiDot mode")
    }
}
