import AppKit
import AutoHushKit
import AutoHushPlayers
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
    /// How Reopen AutoHush opens it again once it has quit, then quits it
    /// (`reopenAutoHush`). Tests replace them.
    var openAfterExit: @MainActor (URL) throws -> Void = { _ = try RelaunchWaiter.openAfterExit($0) }
    var terminateToReopen: @MainActor () -> Void = { NSApp.terminate(nil) }
    /// The Settings window's content, which reads what it shows from its owners.
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
    var player: any MusicPlayer? { session.player }
    /// Asks for the media player while none is chosen; made when first needed.
    var playerChooser: any PlayerChooserPresenting?
    let makePlayerChooser: @MainActor (SettingsModel) -> any PlayerChooserPresenting
    /// Learning the chosen player's controls with the user, when it's one
    /// AutoHush must learn (a Safari web app).
    let learning = LearningSession()
    /// Asks to play and pause a player AutoHush must learn, once it's chosen.
    var learningWindow: any LearningWindowPresenting?
    let makeLearningWindow: @MainActor (SettingsModel) -> any LearningWindowPresenting
    /// Makes a web app from an address and chooses it ("Add a Web App…"):
    /// its model, its window and the add under way.
    private(set) var addWebApp: AddWebAppFeature!
    /// Checks an app and adds it ("Add an App…"): its model, its windows,
    /// the check's panel and the Mac's output muted during a check.
    private(set) var addApp: AddAppFeature!
    /// Lowers the Mac's volume as the music resumes after quieter apps
    /// (Settings → Behavior): one for every monitoring.
    let volumeLeveler: SystemVolumeLeveler
    /// Where Now Playing shown for a press is kept until it's hidden again,
    /// and the setting itself (`NowPlayingSetting.restoreIfLeft`).
    let nowPlayingDefaults: UserDefaults
    let nowPlayingSetting: NowPlayingSetting.Setting
    /// Opens an app (the player, as the learning window opens).
    let openApp: @MainActor (URL) async -> Void
    /// The learning window shows both steps ticked this long before closing.
    let learnedWindowDelay: Duration
    /// Update checks (menu, Settings and the daily automatic one), downloads,
    /// installs and their notifications.
    private(set) var updates: UpdateController!
    /// Where macOS's notices of apps opening and of the Mac sleeping and
    /// waking come: NSWorkspace's own; tests post their own.
    let workspaceCenter: NotificationCenter
    var playerLaunchObserver: any NSObjectProtocol?
    /// The Mac going to sleep and waking up.
    var sleepObservers: [any NSObjectProtocol] = []
    let logger = AutoHushLogger(category: "AppDelegate")
    /// Copies of AutoHush opened before this one, which quit when it opens.
    let otherInstances: OtherInstances
    /// Turns SIGTERM into a normal quit.
    var terminationSignal: any DispatchSourceSignal?
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

    /// What AutoHush works through: its preferences and choices, the
    /// players, the updates, Add an App's and Add a Web App's systems, the
    /// windows it makes, macOS's notices, the clock and the waits. Tests
    /// replace them.
    @MainActor
    struct System {
        var preferences = Preferences()
        var defaults: UserDefaults = .standard
        var launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController()
        var updateSystem = UpdateController.System()
        var players: MusicPlayerCatalog = SupportedPlayers.catalog
        var checkedPlayers: CheckedPlayers = SupportedPlayers.checkedPlayers
        var addAppSystem = AddAppFeature.System()
        var volumeLeveler = SystemVolumeLeveler()
        var nowPlayingDefaults: UserDefaults = .standard
        var nowPlayingSetting: NowPlayingSetting.Setting = .controlCenter
        /// `nil`: `PlayerSession.pipelines`, with `volumeLeveler`.
        var makeMonitoring: PlayerSession.MakeMonitoring?
        var locateApp: PlayerOption.Locate = PlayerOption.locateInstalledApp
        var makePlayerChooser: @MainActor (SettingsModel) -> any PlayerChooserPresenting = {
            PlayerChooserWindowController(model: $0)
        }
        var makeLearningWindow: @MainActor (SettingsModel) -> any LearningWindowPresenting = {
            LearningWindowController(model: $0)
        }
        var webAppMaker: any WebAppMaking = SupportedPlayers.webAppMaker
        var makeAddWebAppWindow: @MainActor (AddWebAppModel, SettingsModel) -> any AddWebAppPresenting = {
            AddWebAppWindowController(model: $0, settings: $1)
        }
        var openApp: @MainActor (URL) async -> Void = { url in
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                AutoHushLogger(category: "AppDelegate").error(
                    "Couldn't open \(url.lastPathComponent, privacy: .public): \(error)")
            }
        }
        var learnedWindowDelay: Duration = .seconds(1.5)
        var madeWebAppWait: Duration = .milliseconds(500)
        var otherInstances: OtherInstances = .live(bundleIdentifier: ProjectInfo.bundleID)
        var retries = PlayerSession.Retries()
        var watchFolder: FolderWatch.Start = FolderWatch.start
        var installCheckDelay: Duration = .seconds(1)
        var permissionCenter = PermissionCenter()
        var windowWatchSleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
        var workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
        var clock: @MainActor () -> Date = Date.init
        var hasOpenWindow: @MainActor () -> Bool = { NSApplication.shared.windows.contains { $0.isOpen && $0.canBecomeKey } }
    }

    init(system: System = System()) {
        self.preferences = system.preferences
        self.defaults = system.defaults
        self.players = system.players
        self.checkedPlayers = system.checkedPlayers
        self.volumeLeveler = system.volumeLeveler
        self.nowPlayingDefaults = system.nowPlayingDefaults
        self.nowPlayingSetting = system.nowPlayingSetting
        self.locateApp = system.locateApp
        self.makePlayerChooser = system.makePlayerChooser
        self.makeLearningWindow = system.makeLearningWindow
        self.learnedWindowDelay = system.learnedWindowDelay
        self.openApp = system.openApp
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
            makeMonitoring: system.makeMonitoring
                ?? PlayerSession.pipelines(hostedApp: SupportedPlayers.hostedApp(pid:), volumeLeveler: volumeLeveler),
            locateApp: locateApp,
            retries: system.retries
        )
        self.otherInstances = system.otherInstances
        self.watchFolder = system.watchFolder
        self.installCheckDelay = system.installCheckDelay
        self.permissionCenter = system.permissionCenter
        self.workspaceCenter = system.workspaceCenter
        self.clock = system.clock
        self.hasOpenWindow = system.hasOpenWindow
        super.init()
        session.didChange = { [weak self] _ in self?.showSession() }
        userSettings.didChange = { [weak self] in self?.showUserSettings($0) }
        learning.didChange = { [weak self] in self?.showLearning($0) }
        updates = UpdateController(
            system: system.updateSystem,
            preferences: preferences,
            isQuietMoment: { [weak self] in self?.isQuietMoment ?? false },
            quit: { [weak self] in self?.quitFromRunLoop() },
            onOffer: { [weak self] in self?.status.updateOffer = $0 }
        )
        updates.beforePresenting = { [weak self] in self?.statusMenu?.close() }
        addApp = AddAppFeature(host: self, system: system.addAppSystem, keptChecks: KeptCheckStore(defaults: defaults))
        addWebApp = AddWebAppFeature(host: self, maker: system.webAppMaker, makeWindow: system.makeAddWebAppWindow, openApp: openApp,
                                     learnedWindowDelay: learnedWindowDelay, madeWebAppWait: system.madeWebAppWait,
                                     exampleAddress: players.exampleWebAddress, countrySites: players.countrySites)
        settingsModel = SettingsModel(
            state: appState,
            settings: userSettings,
            updates: updates,
            permissionCenter: permissionCenter,
            learningSession: learning,
            actions: self,
            launchAtLoginController: system.launchAtLoginController,
            menuBarIcon: MenuBarIconPlace(defaults: defaults)
        )
        windowWatch = WindowWatch(sleep: system.windowWatchSleep,
                                  refresh: { [weak self] in await self?.refresh($0) },
                                  everyTick: { [weak self] in self?.followWelcomeClosed() })
        registerWatchedWindows()
        showChosenPlayer()
        refreshPlayerOptions()
        showUserSettings(userSettings.state)
        followPlayerReopen() // the chosen player may be running without what it needs
        learning.follow(player) // as the session does, from the start (`setChosenPlayer`)
    }
}

// MARK: - What only AppDelegate does

extension AppDelegate: AppActions {
    /// The menu's, Settings' and the welcome window's choice: as AutoHush's
    /// own (`AppDelegate+Player`), then the permissions read again, as the
    /// menu stays open and its card's checks follow the new player's.
    func choosePlayer(_ bundleID: String) {
        switchPlayer(to: bundleID, showsLearningWindow: true)
        Task { [weak self] in await self?.refreshPermissions() }
    }
    func openAddWebApp() { addWebApp.show() }
    func openAddApp() { addApp.open() }
    func unmutePlayer() {
        guard let player else { return }
        logger.notice("\(player.name, privacy: .public) unmuted from the menu, until the other apps stop")
        // Muted in place of its pause: AutoHush's own mute, lifted by the session.
        if status.playerMutedInstead {
            session.unmuteInstead()
            return
        }
        // Its state then reads as playing: the user's, as a resume by hand.
        Task { [weak self] in
            do {
                try await player.play()
            } catch {
                self?.logger.error("\(player.name, privacy: .public) couldn’t be unmuted: \(error)")
                self?.tellFailure(PlayerAlerts.couldNotUnmute(player.name))
            }
        }
    }
    func openNotificationSettings() { SystemSettingsPane.notifications.open() }

    func moveMenuBarIconNearSystemIcons() {
        statusMenu?.remove()
        showStatusMenu()
    }
    var menuBarIconIsHidden: Bool { MenuBarIconVisibility.isHidden(statusMenu?.statusItem.button) }
    func retryResume() { session.retryResume() }
    func showLogs() {
        if logsWindowController == nil { logsWindowController = LogsWindowController(model: LogsModel()) }
        logsWindowController?.show()
    }
    func quit() { NSApp.terminate(nil) }
}
