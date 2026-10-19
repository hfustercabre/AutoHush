import AppKit
import Observation
import Testing
@testable import AutoHushApp
import AutoHushKit
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

    /// The user's settings, with these apps seen and ignored.
    private func userSettings(seen: [AudioSource], ignored: [AudioSource] = []) -> UserSettings {
        let preferences = Preferences(store: InMemoryPreferenceStore())
        preferences.recordSeen(seen)
        preferences.ignoredApps = ignored
        return UserSettings(preferences: preferences)
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
        model.currentVersion = "1.2.3"
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
        #expect(DetectionSettingsView.unavailableNote("Muted") == "Unavailable with Muted: AutoHush can only mute it, which needs Audio Recording, and AntiDot mode doesn’t use it.")
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

    @Test("the apps list merges seen and ignored apps, the most recent first, then those that never played")
    func appsList() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC", bundlePath: "/Applications/VLC.app")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        show(model, seen: [vlc, chrome], ignored: [AudioSource(id: vlc.id, name: "VLC"), zoom])

        #expect(model.apps.map(\.source.name) == ["VLC", "Google Chrome", "zoom.us"])
        #expect(model.apps.map(\.isIgnored) == [true, false, true])
        #expect(model.apps.map(\.playedRank) == [0, 1, nil])
        #expect(model.apps[0].source.bundlePath == "/Applications/VLC.app") // the seen entry keeps its icon
    }

    @Test("the apps can be ordered by last played, name or on/off, each either way round")
    func appsOrder() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        let arc = AudioSource(id: "company.thebrowser.Browser", name: "Arc")
        // Played most recently: Safari, VLC, Chrome, Arc; zoom was ignored without playing.
        show(model, seen: [safari, vlc, chrome, arc], ignored: [vlc, zoom])
        /// What Sort by says of the way round, then the apps in that order.
        func names(_ criterion: AppListOrder.Criterion, reversed: Bool = false) -> [String] {
            model.setAppListOrder(AppListOrder(criterion: criterion, isReversed: reversed))
            return [model.appListOrder.directionTitle] + model.apps.map(\.source.name)
        }

        #expect(names(.lastPlayed) == ["Newest first", "Safari", "VLC", "Google Chrome", "Arc", "zoom.us"])
        #expect(names(.lastPlayed, reversed: true) == ["Oldest first", "zoom.us", "Arc", "Google Chrome", "VLC", "Safari"])
        #expect(names(.name) == ["A to Z", "Arc", "Google Chrome", "Safari", "VLC", "zoom.us"])
        #expect(names(.name, reversed: true) == ["Z to A", "zoom.us", "VLC", "Safari", "Google Chrome", "Arc"])
        // Each group stays A to Z; reversed, only the groups swap.
        #expect(names(.state) == ["Apps that pause playback first", "Arc", "Google Chrome", "Safari", "VLC", "zoom.us"])
        #expect(names(.state, reversed: true) == ["Ignored apps first", "VLC", "zoom.us", "Arc", "Google Chrome", "Safari"])

        // New apps arrive in the chosen order.
        model.setAppListOrder(AppListOrder(criterion: .name, isReversed: true))
        show(model, seen: [chrome, safari], ignored: [])
        #expect(model.apps.map(\.source.name) == ["Safari", "Google Chrome"])
    }

    @Test("the search narrows the apps to the names that match, ignoring case and accents, in the chosen order")
    func appSearch() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let facetime = AudioSource(id: "com.apple.FaceTime", name: "FaceTime")
        let musica = AudioSource(id: "com.example.musica", name: "Música")
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        show(model, seen: [facetime, safari, chrome, musica], ignored: [])
        #expect(model.shownApps == model.apps) // closed

        model.appSearch = ""
        #expect(model.shownApps == model.apps) // open, nothing typed
        model.appSearch = " ME "
        #expect(model.shownApps.map(\.source.name) == ["FaceTime", "Google Chrome"])
        model.appSearch = "musi"
        #expect(model.shownApps.map(\.source.name) == ["Música"])
        model.appSearch = "zoom"
        #expect(model.shownApps.isEmpty)

        model.appSearch = "a"
        model.setAppListOrder(AppListOrder(criterion: .name))
        #expect(model.shownApps.map(\.source.name) == ["FaceTime", "Música", "Safari"])
    }

    @Test("choosing an order is passed on once; the stored order is shown from the start")
    func appsOrderChoice() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(model.appListOrder == .standard)

        model.setAppListOrder(AppListOrder(criterion: .name, isReversed: true))
        model.setAppListOrder(AppListOrder(criterion: .name, isReversed: true))
        #expect(model.settings.state.listOrder == AppListOrder(criterion: .name, isReversed: true))

        let stored = UserSettings.inMemory()
        stored.setListOrder(AppListOrder(criterion: .state))
        let reopened = makeModel(MockLaunchAtLoginController(isEnabled: false), settings: stored)
        #expect(reopened.appListOrder == AppListOrder(criterion: .state))
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
        withObservationTracking { _ = model.apps } onChange: { apps.increment() }
        model.state.status.playback = .pausedByMonitor
        model.state.status.setActiveSources([chrome])
        #expect(apps.value == 0)

        let line = Locked(0)
        withObservationTracking { _ = model.statusLine } onChange: { line.increment() }
        show(model, seen: [vlc, chrome], ignored: [vlc])
        #expect(line.value == 0)
        #expect(apps.value == 1)
        #expect(model.apps.map(\.id) == [vlc.id, chrome.id])
        model.state.status.playback = .musicPlaying
        #expect(line.value == 1)

        let order = Locked(0)
        withObservationTracking { _ = model.apps } onChange: { order.increment() }
        model.setAppListOrder(AppListOrder(criterion: .name))
        #expect(order.value == 1)
        #expect(model.apps.map(\.id) == [chrome.id, vlc.id])
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
        model.currentVersion = "0.3.11"
        #expect(model.updateTitle == "AutoHush 0.3.11")
        #expect(model.lastCheckedNote() == nil)

        let now = Date()
        model.lastUpdateCheck = now.addingTimeInterval(-2 * 3600)
        model.updateStatus = "AutoHush 0.3.11 is up to date."
        #expect(model.updateTitle == "AutoHush 0.3.11 is up to date.")
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: now.addingTimeInterval(-2 * 3600), relativeTo: now)
        #expect(model.lastCheckedNote(now: now) == "Last checked \(when)")
    }

    // MARK: - Sound Sources

    /// Five apps, listed in this order (Last Played, the most recent first).
    private static let listed = ["Arc", "Books", "Chess", "Discord", "Edge"].map {
        AudioSource(id: "com.example.\($0.lowercased())", name: $0)
    }
    private static let ids = listed.map(\.id)

    /// The model listing `listed`, `ignored` turned off, and the user's settings it removes them from.
    private func listing(ignored: [AudioSource] = []) -> (model: SettingsModel, settings: UserSettings) {
        let settings = userSettings(seen: Self.listed, ignored: ignored)
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false), settings: settings)
        show(model, seen: Self.listed, ignored: ignored)
        return (model, settings)
    }

    /// The selected apps' IDs, in the list's order.
    private func selected(_ model: SettingsModel) -> [String] { model.selectedApps.map(\.id) }

    @Test("a click selects only that app, a second click on it alone unselects it, and a click on one of several selects only that one")
    func plainClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[1])
        #expect(selected(model) == [ids[1]])
        model.click(on: ids[3])
        #expect(selected(model) == [ids[3]])
        model.click(on: ids[3])
        #expect(selected(model).isEmpty)

        model.click(on: ids[0])
        model.click(on: ids[2], command: true)
        model.click(on: ids[2])
        #expect(selected(model) == [ids[2]])
    }

    @Test("⌘-click adds an app to the selection or takes it out")
    func commandClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[0])
        model.click(on: ids[3], command: true)
        model.click(on: ids[1], command: true)
        #expect(selected(model) == [ids[0], ids[1], ids[3]]) // in the list's order
        model.click(on: ids[0], command: true)
        #expect(selected(model) == [ids[1], ids[3]])
    }

    @Test("⇧-click selects the apps from the last one clicked, either way; a second one changes the range, keeping what ⌘ added")
    func shiftClick() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        #expect(selected(model) == [ids[1], ids[2], ids[3]])
        model.click(on: ids[0], shift: true) // from the same app, the other way
        #expect(selected(model) == [ids[0], ids[1]])

        model.click(on: ids[4], command: true) // where the next range starts
        model.click(on: ids[3], shift: true)
        #expect(selected(model) == [ids[0], ids[1], ids[3], ids[4]])

        model.click(on: ids[2]) // starts over
        model.click(on: ids[4], command: true, shift: true) // ⇧ with ⌘ too
        #expect(selected(model) == [ids[2], ids[3], ids[4]])
    }

    @Test("⇧-click before any click adds just that app, and the next ⇧-click selects from it")
    func shiftClickFirst() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[2], shift: true)
        #expect(selected(model) == [ids[2]])
        model.click(on: ids[4], shift: true)
        #expect(selected(model) == [ids[2], ids[3], ids[4]])

        model.click(on: ids[4]) // only this one…
        model.click(on: ids[4]) // …then none: nothing to select from
        model.click(on: ids[1], shift: true)
        #expect(selected(model) == [ids[1]])
    }

    @Test("Return or Space on a row adds it to the selection or takes it out, and a ⇧-click selects from it")
    func keyboardToggle() {
        let model = listing().model, ids = Self.ids
        model.toggleSelection(of: ids[1])
        model.toggleSelection(of: ids[3])
        #expect(selected(model) == [ids[1], ids[3]])
        model.toggleSelection(of: ids[1])
        #expect(selected(model) == [ids[3]])
        model.click(on: ids[4], shift: true)
        #expect(selected(model) == [ids[1], ids[2], ids[3], ids[4]])
    }

    @Test("Remove takes an app that pauses the music off the list at once, and its selection with it")
    func removeAppThatPauses() {
        let (model, settings) = listing()
        model.click(on: Self.ids[2])
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [Self.ids[0], Self.ids[1], Self.ids[3], Self.ids[4]]) // forgotten
        #expect(model.selectedApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
    }

    @Test("Remove takes several apps that pause the music off the list at once")
    func removeSeveralThatPause() {
        let (model, settings) = listing()
        let ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], command: true)
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[2], ids[4]])
        #expect(model.selectedApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
    }

    @Test("Remove asks first for an app that's turned off: confirming forgets it, cancelling keeps it")
    func removeTurnedOffApp() {
        let zoom = AudioSource(id: "us.zoom.xos", name: "zoom.us")
        let settings = userSettings(seen: [zoom], ignored: [zoom])
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false), settings: settings)
        show(model, seen: [zoom], ignored: [zoom])
        let row = model.apps[0]

        model.remove(row)
        #expect(settings.state.seenApps == [zoom]) // not yet: it's asked first
        #expect(model.appsAwaitingRemoval == [row])
        #expect(model.removalNames == ["zoom.us"])
        model.cancelRemoval()
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(settings.state.seenApps == [zoom])

        model.click(on: row.id) // selected, the same
        model.removeSelected()
        #expect(model.appsAwaitingRemoval == [row])
        model.confirmRemoval()
        #expect(settings.state.seenApps.isEmpty && settings.state.ignoredApps.isEmpty)
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(model.selectedApps.isEmpty)
        model.confirmRemoval() // nothing waits any more
    }

    @Test("Remove asks once for several apps when one is turned off: confirming forgets them all, cancelling keeps them")
    func removeSeveralWithTurnedOff() {
        let (model, settings) = listing(ignored: [Self.listed[2]])
        let ids = Self.ids
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        model.removeSelected()
        #expect(settings.state.seenApps == Self.listed) // not yet: it's asked first
        #expect(model.appsAwaitingRemoval.map(\.id) == [ids[1], ids[2], ids[3]])
        #expect(model.removalNames == ["Books", "Chess", "Discord"])
        model.cancelRemoval()
        #expect(model.appsAwaitingRemoval.isEmpty)
        #expect(model.removalNames.count == 3) // kept while the confirmation closes
        #expect(selected(model) == [ids[1], ids[2], ids[3]]) // still selected
        #expect(settings.state.seenApps == Self.listed)

        model.removeSelected()
        model.confirmRemoval()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[4]])
        #expect(settings.state.ignoredApps.isEmpty)
        #expect(model.selectedApps.isEmpty)
    }

    @Test("Remove from List takes its own app when it isn't one of several selected, else the whole selection, as Finder")
    func removeFromList() {
        let (model, settings) = listing()
        let ids = Self.ids, rows = model.apps
        model.click(on: ids[0])
        model.click(on: ids[1], command: true)
        model.removeFromList(rows[3]) // not selected: only it
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[1], ids[2], ids[4]])
        #expect(selected(model) == [ids[0], ids[1]])
        model.removeFromList(rows[1]) // one of the selected: both
        #expect(settings.state.seenApps.map(\.id) == [ids[2], ids[4]])
        #expect(model.selectedApps.isEmpty)
        model.click(on: ids[2])
        model.removeFromList(rows[2]) // selected alone: itself
        #expect(settings.state.seenApps.map(\.id) == [ids[4]])
    }

    @Test("the removal's confirmation names the app for one, says how many for several, and names the one turned off when only one is")
    func removalConfirmation() {
        let (model, _) = listing(ignored: [Self.listed[2]])
        let rows = model.apps
        #expect(SoundSourcesSettingsView.removalTitle(names: ["Chess"]) == "Remove Chess from the list?")
        #expect(SoundSourcesSettingsView.removalTitle(names: ["Books", "Chess"]) == "Remove 2 apps from the list?")
        #expect(SoundSourcesSettingsView.removalMessage([rows[2]]).hasPrefix("Chess is turned off now."))
        #expect(SoundSourcesSettingsView.removalMessage([rows[1], rows[2], rows[3]]).hasPrefix("Chess is turned off now."))
        let (both, _) = listing(ignored: [Self.listed[1], Self.listed[2]])
        #expect(SoundSourcesSettingsView.removalMessage(Array(both.apps[1...2])).hasPrefix("Some of them are turned off now."))
    }

    @Test("the menu says why a switch can't be changed as a fragment, without a period; nothing while it can")
    func unavailableReasons() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        #expect(SettingsSwitch.allCases.allSatisfy { $0.unavailableReason(model) == nil })
        model.setAntiDotMode(true)
        #expect(SettingsSwitch.levelsMusic.unavailableReason(model) == "Off in AntiDot mode")
    }

    @Test("Remove takes only the selected apps the search shows: the hidden ones stay selected, and a range skips them")
    func selectionWhileSearching() {
        let (model, settings) = listing()
        let ids = Self.ids
        model.appSearch = "o" // Books, Discord
        model.click(on: ids[1])
        model.click(on: ids[3], shift: true)
        model.appSearch = nil
        #expect(selected(model) == [ids[1], ids[3]]) // not Chess, hidden between them

        model.click(on: ids[0])
        model.click(on: ids[4], shift: true) // all five
        model.appSearch = "s" // Books, Chess, Discord
        #expect(selected(model) == [ids[1], ids[2], ids[3]])
        model.removeSelected()
        #expect(settings.state.seenApps.map(\.id) == [ids[0], ids[4]])
        model.appSearch = nil
        #expect(selected(model) == [ids[0], ids[4]])
    }

    @Test("an app the search hides isn't removed and comes back selected; closing Settings clears the selection")
    func hiddenSelection() {
        let model = listing().model, ids = Self.ids
        model.click(on: ids[4])
        model.appSearch = "boo"
        #expect(model.selectedApps.isEmpty) // hidden: Remove is unavailable
        model.appSearch = nil
        #expect(selected(model) == [ids[4]])
        model.clearSelection()
        #expect(model.selectedApps.isEmpty)
    }
}
