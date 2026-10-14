import AppKit
import OSLog
import AutoHushKit
import AutoHushPlayers

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
    /// The Settings window's content, kept in sync with the app's state.
    private(set) var settingsModel: SettingsModel!
    var settingsWindowController: SettingsWindowController?
    /// Follows what the open windows show that macOS doesn't announce.
    private(set) var windowWatch: WindowWatch!
    /// The music players to choose from.
    let players: MusicPlayerCatalog
    let locateApp: PlayerOption.Locate
    /// The music player AutoHush pauses and resumes; `nil` until one is chosen.
    var player: (any MusicPlayer)? { session.player }
    /// Asks for the music player while none is chosen; made when first needed.
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
    let logger = Logger(category: "AppDelegate")
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

    init(
        preferences: Preferences = Preferences(),
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        updateChecker: UpdateChecker = UpdateChecker(),
        updateInstaller: any UpdateInstalling = UpdateInstaller(),
        updateNotifier: any UpdateNotifying = SystemUpdateNotifier(),
        updateDownloadsFolder: URL = UpdateDownloads.defaultFolder,
        players: MusicPlayerCatalog = SupportedPlayers.catalog,
        makeMonitoring: @escaping PlayerSession.MakeMonitoring = PlayerSession.pipelines(hostedApp: SupportedPlayers.hostedApp(pid:)),
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
                Logger(category: "AppDelegate").error(
                    "Couldn't open \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
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
        windowWatchSleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.preferences = preferences
        self.players = players
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
            makeMonitoring: makeMonitoring,
            locateApp: locateApp,
            retries: retries
        )
        self.otherInstances = otherInstances
        self.watchFolder = watchFolder
        self.installCheckDelay = installCheckDelay
        self.permissionCenter = permissionCenter
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
        learning.follow(player) // as the session does, from the start (`setChosenPlayer`)
        addWebAppModel.exampleAddress = players.exampleWebAddress
        addWebAppModel.countrySites = players.countrySites
        addWebAppModel.start = { [weak self] in self?.addWebApp(from: $0) }
        addWebAppModel.cancel = { [weak self] in self?.cancelAddingWebApp() }
        addWebAppModel.openAccessibilitySettings = { [weak self] in self?.requestPermission(.accessibility(player: "Safari")) }
    }
}

// MARK: - What only AppDelegate does

extension AppDelegate: AppActions {
    func choosePlayer(_ bundleID: String) { chooseMusicPlayer(bundleID) }
    func openAddWebApp() { showAddWebApp() }
    func reopenAutoHush() { reopen() }
    func openNotificationSettings() { SystemSettingsPane.notifications.open() }
    func quit() { NSApp.terminate(nil) }
}
