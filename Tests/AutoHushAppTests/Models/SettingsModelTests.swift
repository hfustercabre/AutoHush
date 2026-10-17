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

        let reopen = Changes()
        withObservationTracking { _ = model.offersReopenPlayer } onChange: { reopen.count += 1 }
        model.state.status.playerNeedsReopen = true
        #expect(reopen.count == 1)
        #expect(model.offersReopenPlayer)
        model.state.status.playerNeedsReopen = false

        let unmute = Changes()
        withObservationTracking { _ = model.offersUnmute } onChange: { unmute.count += 1 }
        model.state.status.playerMutes = true
        model.state.status.setActiveSources([AudioSource(id: "com.apple.Safari", name: "Safari")])
        model.state.status.playback = .pausedByMonitor
        #expect(unmute.count == 1)
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

        let apps = Changes()
        withObservationTracking { _ = model.apps } onChange: { apps.count += 1 }
        model.state.status.playback = .pausedByMonitor
        model.state.status.setActiveSources([chrome])
        #expect(apps.count == 0)

        let line = Changes()
        withObservationTracking { _ = model.statusLine } onChange: { line.count += 1 }
        show(model, seen: [vlc, chrome], ignored: [vlc])
        #expect(line.count == 0)
        #expect(apps.count == 1)
        #expect(model.apps.map(\.id) == [vlc.id, chrome.id])
        model.state.status.playback = .musicPlaying
        #expect(line.count == 1)

        let order = Changes()
        withObservationTracking { _ = model.apps } onChange: { order.count += 1 }
        model.setAppListOrder(AppListOrder(criterion: .name))
        #expect(order.count == 1)
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

    @Test("each page's Restore Defaults restores the settings it shows only: Detection's timings, or the fades")
    func restoreDefaults() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let changed = TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40,
                                     fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false)
        model.setTimings(changed)
        #expect(!model.detectionTimingsAreDefaults && !model.fadesAreDefaults)

        model.restoreDefaultDetectionTimings()
        #expect(model.detectionTimingsAreDefaults)
        #expect(!model.fadesAreDefaults) // the other page keeps its own
        #expect(model.timings == TimingSettings(fadeOutDuration: 3, fadeInDuration: 4, fadesEnabled: false))

        model.setTimings(changed)
        model.restoreDefaultFades()
        #expect(model.fadesAreDefaults)
        #expect(!model.detectionTimingsAreDefaults)
        #expect(model.timings == TimingSettings(startConfirmation: 2, stopGrace: 7, silenceThresholdDB: -40))

        // In AntiDot mode the silence threshold is hidden: it neither lights
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

    @Test("Remove takes an app that pauses the music off the list at once, and its selection with it")
    func removeAppThatPauses() {
        let chrome = AudioSource(id: "com.google.Chrome", name: "Google Chrome")
        let settings = userSettings(seen: [chrome])
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false), settings: settings)
        show(model, seen: [chrome], ignored: [])
        model.toggleSelection(of: chrome.id)
        #expect(model.selectedApp?.id == chrome.id)

        model.remove(model.selectedApp!)
        #expect(settings.state.seenApps.isEmpty) // forgotten
        #expect(model.selectedApp == nil)
        #expect(model.appAwaitingRemoval == nil)
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
        #expect(model.appAwaitingRemoval?.id == zoom.id)
        #expect(model.removalName == "zoom.us")
        model.cancelRemoval()
        #expect(model.appAwaitingRemoval == nil)
        #expect(settings.state.seenApps == [zoom])

        model.remove(row)
        model.confirmRemoval()
        #expect(settings.state.seenApps.isEmpty && settings.state.ignoredApps.isEmpty)
        #expect(model.appAwaitingRemoval == nil)
        model.confirmRemoval() // nothing waits any more
    }

    @Test("a click selects an app and a second one unselects it; an app the search hides can't be removed")
    func selection() {
        let model = makeModel(MockLaunchAtLoginController(isEnabled: false))
        let safari = AudioSource(id: "com.apple.Safari", name: "Safari")
        let vlc = AudioSource(id: "org.videolan.vlc", name: "VLC")
        show(model, seen: [safari, vlc], ignored: [])
        model.toggleSelection(of: vlc.id)
        model.toggleSelection(of: vlc.id)
        #expect(model.selectedApp == nil)

        model.toggleSelection(of: vlc.id)
        model.appSearch = "saf"
        #expect(model.selectedApp == nil) // hidden: Remove is unavailable
        model.appSearch = nil
        #expect(model.selectedApp?.id == vlc.id)
        model.clearSelection()
        #expect(model.selectedApp == nil)
    }


}

/// One at a time: each window takes the name its place is kept under, which
/// a second window can't have while the first exists.
@Suite("SettingsWindowController", .serialized)
@MainActor
struct SettingsWindowControllerTests {
    private let actions = FakeAppActions()
    private let updates = FakeUpdateCommands()

    private func makeModel() -> SettingsModel {
        SettingsModel(settings: .inMemory(), updates: updates, actions: actions,
                      launchAtLoginController: MockLaunchAtLoginController(isEnabled: false))
    }

    @Test("has a sidebar of pages in three groups beside the page, and opens on the one asked for, named in the title; centered the first time")
    func pages() throws {
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(SettingsWindowController.frameName)") // never opened before
        let sut = SettingsWindowController(model: makeModel())
        let split = try #require(sut.window?.contentViewController as? NSSplitViewController)
        #expect(split.splitViewItems.count == 2)
        #expect(split.splitViewItems.first?.behavior == .sidebar)
        #expect(SettingsWindowController.Page.groups.map { $0.map(\.title) }
                == [["General", "Sound Sources"], ["Detection", "Fades"], ["Diagnostics", "Updates", "About"]])
        #expect(Set(SettingsWindowController.Page.groups.joined()) == Set(SettingsWindowController.Page.allCases))
        #expect(sut.shownPage == nil) // not on screen

        sut.show(page: .diagnostics)
        defer { sut.close() }
        let window = try #require(sut.window)
        let area = try #require(window.screen?.visibleFrame)
        #expect(abs(window.frame.midX - area.midX) <= 1)
        #expect(sut.shownPage == .diagnostics)
        #expect(sut.window?.title == "Diagnostics")
        sut.show(page: .about) // the menu's About button
        #expect(sut.shownPage == .about)
        #expect(sut.window?.title == "About")
    }

    @Test("the window resizes between its limits; the sidebar keeps its width")
    func limits() throws {
        let sut = SettingsWindowController(model: makeModel())
        let window = try #require(sut.window)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.contentMinSize == NSSize(width: 715, height: 560))
        #expect(window.contentMaxSize == NSSize(width: 875, height: 900))
        let sidebar = try #require((window.contentViewController as? NSSplitViewController)?.splitViewItems.first)
        #expect(sidebar.minimumThickness == SettingsWindowController.sidebarWidth)
        #expect(sidebar.maximumThickness == SettingsWindowController.sidebarWidth)
        #expect(!sidebar.canCollapse)
        // Kept between launches: the controller gives its window its name
        // (on macOS 14 and 15 it would clear one set before).
        #expect(sut.windowFrameAutosaveName == SettingsWindowController.frameName)
        #expect(window.frameAutosaveName == SettingsWindowController.frameName)
        #expect(window.collectionBehavior.contains(.fullScreenNone)) // never full screen
    }

    @Test("closed and opened again, Settings is back on General; while open, it keeps its page")
    func reopensOnGeneral() {
        let sut = SettingsWindowController(model: makeModel())
        defer { sut.close() }
        sut.show()
        #expect(sut.shownPage == .general)
        sut.show(page: .detection)
        sut.show() // Settings in the menu while the window is open
        #expect(sut.shownPage == .detection)

        sut.close()
        sut.show()
        #expect(sut.shownPage == .general)
    }

    @Test("minimized, Settings is still open: it keeps its page, and shows again as it was")
    func minimizedIsOpen() async throws {
        let model = makeModel()
        let sut = SettingsWindowController(model: model)
        defer { sut.close() }
        sut.show(page: .detection)
        model.foldedDiagnostics = [.apps]
        let window = try #require(sut.window)
        window.miniaturize(nil)
        await TestWait.until { window.isMiniaturized }
        #expect(!window.isVisible && window.isOpen) // macOS counts it as not visible
        #expect(sut.shownPage == .detection)

        sut.show() // Settings in the menu
        await TestWait.until { !window.isMiniaturized }
        #expect(!window.isMiniaturized && sut.shownPage == .detection)
        #expect(model.foldedDiagnostics == [.apps]) // not reopened
    }

    @Test("reopened, Sound Sources' search is closed and every part of Diagnostics open")
    func reopensFresh() {
        let model = makeModel()
        let sut = SettingsWindowController(model: model)
        defer { sut.close() }
        sut.show(page: .apps)
        model.appSearch = "chr"
        model.foldedDiagnostics = [.apps]
        sut.show(page: .diagnostics)
        #expect(model.appSearch == "chr") // still open while the window is
        #expect(model.foldedDiagnostics == [.apps])

        sut.close()
        sut.show()
        #expect(model.appSearch == nil)
        #expect(model.foldedDiagnostics.isEmpty)
    }
}

/// How many times what a test followed changed (`withObservationTracking`).
private final class Changes: @unchecked Sendable {
    var count = 0
}
