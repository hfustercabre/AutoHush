import AppKit
import AutoHushKit
import AutoHushPlayers
import CheckPanel
import CheckedPlayers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The app's state, which the menu and the windows show.
    let appState = AppState()
    /// What the menu and the windows show, kept in `appState`; each change
    /// goes to `statusMenu` too, once it exists, which renders its copy.
    var status: AppStatus {
        get { appState.status }
        set {
            guard newValue != appState.status else { return }
            appState.status = newValue
            statusMenu?.status = newValue
        }
    }

    var statusMenu: StatusMenuController?
    /// The chosen player, from its start until AutoHush quits.
    let session: PlayerSession
    /// The user's settings: Auto-Pause, the apps, the timings, detection.
    let userSettings: UserSettings
    /// Turns Auto-Pause on or off during a Focus with AutoHush's filter, and
    /// back after it.
    let focusAutoPause: FocusAutoPause
    let preferences: Preferences
    /// The choices kept beside `preferences`: the players reopened always
    /// (`ReopenChoices`) and Add an App's finished check (`KeptCheckStore`).
    let defaults: UserDefaults
    /// Runs AutoHush's alerts (removing an added app, reopening a player,
    /// the card's info button) and returns the button pressed. Tests replace it.
    var runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = InfoAlert.runInFront
    /// The Settings window's content, kept in sync with the app's state.
    private(set) var settingsModel: SettingsModel!
    var settingsWindowController: SettingsWindowController?
    /// AutoHush's logs, from Settings → Diagnostics; made when first shown.
    var logsWindowController: LogsWindowController?
    /// Follows what the open windows show that macOS doesn't announce.
    private(set) var windowWatch: WindowWatch!
    /// The media players to choose from.
    let players: MusicPlayerCatalog
    /// The apps added with Add an App, which `players` offers: what each
    /// one's check found, kept until it's removed.
    let checkedPlayers: CheckedPlayers
    let locateApp: PlayerOption.Locate
    /// The media player AutoHush pauses and resumes; `nil` until one is chosen.
    var player: (any MusicPlayer)? { session.player }
    /// Asks for the media player while none is chosen; made when first needed.
    var playerChooser: (any PlayerChooserPresenting)?
    let makePlayerChooser: @MainActor (SettingsModel) -> any PlayerChooserPresenting
    /// Learning the chosen player's controls with the user, when it's one
    /// AutoHush must learn (a Safari web app).
    let learning = LearningSession()
    /// Asks to play and pause a player AutoHush must learn, once it's chosen.
    var learningWindow: (any LearningWindowPresenting)?
    let makeLearningWindow: @MainActor (SettingsModel) -> any LearningWindowPresenting
    /// Makes a Safari web app from an address ("Add a Web App…").
    let webAppMaker: any WebAppMaking
    let addWebAppModel = AddWebAppModel()
    var addWebAppWindow: (any AddWebAppPresenting)?
    let makeAddWebAppWindow: @MainActor (AddWebAppModel, SettingsModel) -> any AddWebAppPresenting
    var addingWebApp: Task<Void, Never>?
    /// Checks an app and adds it ("Add an App…"); made when first opened.
    var addAppModel: AddAppModel?
    var addAppWindow: AddAppWindowController?
    /// The list of apps Add an App's first step opens.
    var appChooserWindow: AppChooserWindowController?
    /// Shown before a check starts.
    var checkWarningWindow: CheckWarningWindowController?
    /// The check's progress, at the bottom right of the screen while it runs.
    let checkPanel = CheckPanelController()
    /// The Mac's output, muted while a check runs that can't mute only its app.
    let checkOutputMute: OutputMute
    /// Lowers the Mac's volume as the music resumes after quieter apps
    /// (Settings → Advanced): one for every monitoring.
    let volumeLeveler: SystemVolumeLeveler
    /// Where Now Playing shown for a press is kept until it's hidden again,
    /// and the setting itself (`NowPlayingSetting.restoreIfLeft`).
    let nowPlayingDefaults: UserDefaults
    let nowPlayingSetting: NowPlayingSetting.Setting
    /// A web app made but not found as installed yet, and the address it was
    /// made from, while the add window says so (`pickUpListedWebApp`).
    var webAppAwaitingListing: (bundleID: String, address: String)?
    /// Opens an app (the web app just added, so it can be played).
    let openApp: @MainActor (URL) async -> Void
    /// The learning window shows both steps ticked this long before closing.
    let learnedWindowDelay: Duration
    /// Between two looks for a web app just made that isn't listed yet.
    let madeWebAppWait: Duration
    /// Update checks (menu, Settings and the daily automatic one), downloads,
    /// installs and their notifications.
    private(set) var updates: UpdateController!
    var playerLaunchObserver: (any NSObjectProtocol)?
    /// The Mac going to sleep and waking up.
    var sleepObservers: [any NSObjectProtocol] = []
    let logger = AutoHushLogger(category: "AppDelegate")
    /// Copies of AutoHush opened before this one, which quit when it opens.
    let otherInstances: OtherInstances
    /// Turns SIGTERM into a normal quit.
    var terminationSignal: (any DispatchSourceSignal)?
    /// Reads the permissions AutoHush needs, and asks for them.
    let permissionCenter: PermissionCenter
    /// The player chosen in the welcome window is to be learned: the learning
    /// window opens once the welcome window is done.
    var learningAfterWelcome = false
    /// Watches the Applications folders, and the one holding the chosen
    /// player's app, so AutoHush notices at once when it's uninstalled or
    /// installed again.
    let watchFolder: FolderWatch.Start
    var folderWatches: [String: AnyObject] = [:]
    /// The paths of the folders watched.
    var watchedFolders: Set<String> { Set(folderWatches.keys) }
    /// How long after a change in one of them the players are checked again.
    let installCheckDelay: Duration
    var installCheck: Task<Void, Never>?
    /// A quit under way, until the player has its volume back and a pause
    /// AutoHush held is handed over (`shouldTerminate`). Tests await it.
    var quitting: Task<Void, Never>?
    /// When AutoHush last reopened each player, by bundle ID, and whether it
    /// then gave up reopening it by itself (`reopensByItself`).
    var lastReopens: [String: (at: Date, gaveUp: Bool)] = [:]
    /// The clock `lastReopens` is stamped and read by; tests move it on.
    let clock: @MainActor () -> Date
    /// Whether one of AutoHush's windows or alerts is open (`isQuietMoment`),
    /// from the app's windows, which every test shares: tests answer for it.
    let hasOpenWindow: @MainActor () -> Bool

    init(
        preferences: Preferences = Preferences(),
        defaults: UserDefaults = .standard,
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        updateChecker: UpdateChecker = UpdateChecker(),
        updateInstaller: any UpdateInstalling = UpdateInstaller(),
        updateNotifier: any UpdateNotifying = SystemUpdateNotifier(),
        updateDownloadsFolder: URL = UpdateDownloads.defaultFolder,
        players: MusicPlayerCatalog = SupportedPlayers.catalog,
        checkedPlayers: CheckedPlayers = SupportedPlayers.checkedPlayers,
        checkOutputMute: OutputMute = OutputMute(),
        volumeLeveler: SystemVolumeLeveler = SystemVolumeLeveler(),
        nowPlayingDefaults: UserDefaults = .standard,
        nowPlayingSetting: NowPlayingSetting.Setting = .controlCenter,
        // `nil`: `PlayerSession.pipelines`, with `volumeLeveler`.
        makeMonitoring: PlayerSession.MakeMonitoring? = nil,
        locateApp: @escaping PlayerOption.Locate = PlayerOption.locateInstalledApp,
        makePlayerChooser: @escaping @MainActor (SettingsModel) -> any PlayerChooserPresenting = {
            PlayerChooserWindowController(model: $0)
        },
        makeLearningWindow: @escaping @MainActor (SettingsModel) -> any LearningWindowPresenting = {
            LearningWindowController(model: $0)
        },
        webAppMaker: any WebAppMaking = SupportedPlayers.webAppMaker,
        makeAddWebAppWindow: @escaping @MainActor (AddWebAppModel, SettingsModel) -> any AddWebAppPresenting = {
            AddWebAppWindowController(model: $0, settings: $1)
        },
        openApp: @escaping @MainActor (URL) async -> Void = { url in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                AutoHushLogger(category: "AppDelegate").error(
                    "Couldn't open \(url.lastPathComponent, privacy: .public): \(error)")
            }
        },
        learnedWindowDelay: Duration = .seconds(1.5),
        madeWebAppWait: Duration = .milliseconds(500),
        currentVersion: AppVersion? = .current,
        otherInstances: OtherInstances = .live(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.autohush.AutoHush"),
        retries: PlayerSession.Retries = PlayerSession.Retries(),
        watchFolder: @escaping FolderWatch.Start = FolderWatch.start,
        installCheckDelay: Duration = .seconds(1),
        permissionCenter: PermissionCenter = PermissionCenter(),
        windowWatchSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        clock: @escaping @MainActor () -> Date = Date.init,
        hasOpenWindow: @escaping @MainActor () -> Bool = { NSApplication.shared.windows.contains { $0.isOpen && $0.canBecomeKey } }
    ) {
        self.preferences = preferences
        self.defaults = defaults
        self.players = players
        self.checkedPlayers = checkedPlayers
        self.checkOutputMute = checkOutputMute
        self.volumeLeveler = volumeLeveler
        self.nowPlayingDefaults = nowPlayingDefaults
        self.nowPlayingSetting = nowPlayingSetting
        self.locateApp = locateApp
        self.makePlayerChooser = makePlayerChooser
        self.makeLearningWindow = makeLearningWindow
        self.learnedWindowDelay = learnedWindowDelay
        self.madeWebAppWait = madeWebAppWait
        self.webAppMaker = webAppMaker
        self.makeAddWebAppWindow = makeAddWebAppWindow
        self.openApp = openApp
        // Before anything else is stored: people updating keep their player.
        preferences.keepFormerPlayer(players.formerDefault)
        userSettings = UserSettings(preferences: preferences)
        focusAutoPause = FocusAutoPause(control: userSettings, preferences: preferences)
        // Before launch finishes: macOS may open AutoHush just to run an action.
        IntentDependencies.register(control: userSettings, focus: focusAutoPause)
        session = PlayerSession(
            player: players.player(bundleID: preferences.musicPlayer),
            players: players,
            preferences: preferences,
            settings: userSettings.state.monitoring,
            makeMonitoring: makeMonitoring
                ?? PlayerSession.pipelines(hostedApp: SupportedPlayers.hostedApp(pid:), volumeLeveler: volumeLeveler),
            locateApp: locateApp,
            retries: retries
        )
        self.otherInstances = otherInstances
        self.watchFolder = watchFolder
        self.installCheckDelay = installCheckDelay
        self.permissionCenter = permissionCenter
        self.clock = clock
        self.hasOpenWindow = hasOpenWindow
        super.init()
        session.didChange = { [weak self] _ in self?.showSession() }
        userSettings.didChange = { [weak self] in self?.showUserSettings($0) }
        learning.didChange = { [weak self] in self?.showLearning($0) }
        updates = UpdateController(
            checker: updateChecker,
            installer: updateInstaller,
            notifier: updateNotifier,
            preferences: preferences,
            downloadsFolder: updateDownloadsFolder,
            currentVersion: currentVersion,
            isQuietMoment: { [weak self] in self?.isQuietMoment ?? false },
            quit: { [weak self] in self?.quitToFinishUpdate() },
            onOffer: { [weak self] in self?.status.updateOffer = $0 },
            onStatus: { [weak self] in self?.showUpdateStatus($0) },
            onSettingsChange: { [weak self] in self?.showUpdateSettings() }
        )
        updates.beforePresenting = { [weak self] in await self?.statusMenu?.closeMenu() }
        settingsModel = SettingsModel(
            state: appState,
            settings: userSettings,
            updates: updates,
            learningSession: learning,
            actions: self,
            launchAtLoginController: launchAtLoginController
        )
        settingsModel.checksForUpdatesAutomatically = preferences.checksForUpdatesAutomatically
        settingsModel.automaticUpdates = preferences.automaticUpdates
        settingsModel.updateInstallNote = updates.installUnavailability?.explanation
        settingsModel.currentVersion = currentVersion?.description
        settingsModel.lastUpdateCheck = preferences.lastUpdateCheck
        windowWatch = WindowWatch(sleep: windowWatchSleep,
                                  refresh: { [weak self] in await self?.refresh($0) },
                                  everyTick: { [weak self] in self?.followWelcomeClosed() })
        registerWatchedWindows()
        showChosenPlayer()
        refreshPlayerOptions()
        showUserSettings(userSettings.state)
        followPlayerReopen() // the chosen player may be running without what it needs
        learning.follow(player) // as the session does, from the start (`setChosenPlayer`)
        addWebAppModel.exampleAddress = players.exampleWebAddress
        addWebAppModel.countrySites = players.countrySites
        addWebAppModel.start = { [weak self] in self?.addWebApp(from: $0) }
        addWebAppModel.cancel = { [weak self] in self?.cancelAddingWebApp() }
        addWebAppModel.openAccessibilitySettings = { [weak self] in self?.requestPermission(AddWebAppModel.safariAccess) }
    }
}

// MARK: - What only AppDelegate does

extension AppDelegate: AppActions {
    func choosePlayer(_ bundleID: String) {
        chooseMusicPlayer(bundleID)
        // The menu stays open: its card's checks follow the new player's permission.
        Task { [weak self] in await self?.refreshPermissions() }
    }
    func openAddWebApp() { showAddWebApp() }
    func openAddApp() { showAddApp() }
    func removeAddedApp(_ bundleID: String) { removeAddedAppAfterAsking(bundleID) }
    func reopenPlayer() { reopenChosenPlayer() }
    func unmutePlayer() {
        guard let player else { return }
        logger.notice("\(player.name, privacy: .public) unmuted from the menu, until the other apps stop")
        Task { try? await player.play() } // its state then reads as playing: the user's, as a resume by hand
    }
    func reopenAutoHush() { reopen() }
    func openNotificationSettings() { SystemSettingsPane.notifications.open() }
    func showLogs() {
        if logsWindowController == nil { logsWindowController = LogsWindowController(model: LogsModel()) }
        logsWindowController?.show()
    }
    func quit() { NSApp.terminate(nil) }
}
