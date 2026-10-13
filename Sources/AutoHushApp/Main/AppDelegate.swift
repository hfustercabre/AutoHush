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
    private(set) var status: AppStatus {
        get { appState.status }
        set {
            guard newValue != appState.status else { return }
            appState.status = newValue
            statusMenu?.status = newValue
        }
    }

    private var statusMenu: StatusMenuController?
    /// The chosen player, from its start until AutoHush quits.
    let session: PlayerSession
    /// The user's settings: Auto-Pause, the apps, the timings, detection.
    let userSettings: UserSettings
    let preferences: Preferences
    /// The Settings window's content, kept in sync with the app's state.
    private(set) var settingsModel: SettingsModel!
    private var settingsWindowController: SettingsWindowController?
    /// Follows what the open windows show that macOS doesn't announce.
    private(set) var windowWatch: WindowWatch!
    /// The music players to choose from.
    private let players: MusicPlayerCatalog
    private let locateApp: PlayerOption.Locate
    /// The music player AutoHush pauses and resumes; `nil` until one is chosen.
    var player: (any MusicPlayer)? { session.player }
    /// Asks for the music player while none is chosen; made when first needed.
    private var playerChooser: (any PlayerChooserPresenting)?
    private let makePlayerChooser: @MainActor (SettingsModel) -> any PlayerChooserPresenting
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
    /// Update checks (menu, Settings and the daily automatic one), downloads,
    /// installs and their notifications.
    private(set) var updates: UpdateController!
    private var playerLaunchObserver: (any NSObjectProtocol)?
    /// The Mac going to sleep and waking up.
    private var sleepObservers: [any NSObjectProtocol] = []
    let logger = Logger(category: "AppDelegate")
    /// Copies of AutoHush opened before this one, which quit when it opens.
    private let otherInstances: OtherInstances
    /// Turns SIGTERM into a normal quit.
    private var terminationSignal: (any DispatchSourceSignal)?
    /// Reads the permissions AutoHush needs, and asks for them.
    let permissionCenter: PermissionCenter
    /// The player chosen in the welcome window is to be learned: the learning
    /// window opens once the welcome window is done.
    private var learningAfterWelcome = false
    /// Watches the Applications folders, and the one holding the chosen
    /// player's app, so AutoHush notices at once when it's uninstalled or
    /// installed again.
    private let watchFolder: FolderWatch.Start
    private var folderWatches: [String: AnyObject] = [:]
    /// The paths of the folders watched.
    var watchedFolders: Set<String> { Set(folderWatches.keys) }
    /// How long after a change in one of them the players are checked again.
    private let installCheckDelay: Duration
    private var installCheck: Task<Void, Never>?

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
        self.webAppMaker = webAppMaker
        self.makeAddWebAppWindow = makeAddWebAppWindow
        self.openApp = openApp
        // Before anything else is stored: people updating keep their player.
        preferences.keepFormerPlayer(players.formerDefault)
        userSettings = UserSettings(preferences: preferences)
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
        learning.follow(player)
        addWebAppModel.exampleAddress = players.exampleWebAddress
        addWebAppModel.countrySites = players.countrySites
        addWebAppModel.start = { [weak self] in self?.addWebApp(from: $0) }
        addWebAppModel.cancel = { [weak self] in self?.cancelAddingWebApp() }
        addWebAppModel.openAccessibilitySettings = { [weak self] in self?.requestPermission(.accessibility(player: "Safari")) }
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shown while a window is open: the Mac's standard menus and keys.
        NSApp.mainMenu = MainMenu.make(about: { [weak self] in self?.openSettings(page: .about) },
                                       settings: { [weak self] in self?.openSettings() })
        statusMenu = StatusMenuController(status: status, settings: userSettings, session: session,
                                          updates: updates, actions: self)
        quitOnTerminationSignal()
        registerPlayerLaunchObserver()
        registerSleepObservers()
        // Opened last, this copy is the one that runs: any opened before it
        // quits first, handing over a pause it held, so they never both pause
        // and resume the music.
        let otherInstances = otherInstances
        Task {
            let others = await otherInstances.quitAll()
            if !others.isEmpty { logger.notice("Quit \(others.count) other running AutoHush") }
            session.launch()
            if player == nil { showPlayerChooser() }
        }
        updates.noteLaunch()
        updates.scheduleAutomaticChecks()
    }

    /// Waits (briefly) for a fade in progress to give the player its volume
    /// back, so quitting never leaves the music faded down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A pause AutoHush is holding is handed over (see `PlayerSession.quit`).
        guard let stopping = session.quit() else { return .terminateNow }
        var replied = false
        let reply: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await stopping.value
            reply()
        }
        // Never hang the quit. A timer, not the main queue: it also fires when
        // the quit was asked for from inside a main-actor job.
        let fallback = Timer(timeInterval: 1, repeats: false) { _ in MainActor.assumeIsolated { reply() } }
        RunLoop.main.add(fallback, forMode: .common)
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterPlayerLaunchObserver()
        sleepObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        sleepObservers = []
    }

    // MARK: - Status

    /// Shows what the player session knows in the menu and Settings; with no
    /// player chosen, the status line asks for one, among those listed.
    private func showSession() {
        let state = session.state
        let sourcesChanged = state.activeSources != status.activeSources
        var shown = status
        shown.setHealth(state.health ?? .waitingForPlayer(among: shown.playerOptions))
        shown.setActiveSources(state.activeSources)
        shown.playback = state.playback
        shown.detection = state.detection
        shown.controlError = state.controlError
        if shown != status { status = shown }
        // The monitoring recorded the apps it heard: Settings → Apps lists them.
        if sourcesChanged { userSettings.appsSeenChanged() }
    }

    /// Quits and opens AutoHush again, as macOS's own "Quit & Reopen" does,
    /// handing over a pause it holds.
    func reopen(
        openAfterExit: (URL) throws -> Void = { _ = try UpdateInstaller.openAfterExit($0) },
        terminate: () -> Void = { NSApp.terminate(nil) }
    ) {
        do {
            try openAfterExit(Bundle.main.bundleURL)
        } catch {
            logger.error("Couldn't reopen AutoHush: \(error.localizedDescription, privacy: .public)")
            return
        }
        terminate()
    }

    // MARK: - The user's settings and the updates'

    /// Shows the user's settings in the menu and Settings, and passes what
    /// the monitoring follows on to the player session.
    private func showUserSettings(_ settings: UserSettings.State) {
        status.autoPause = settings.autoPause
        showApps()
        session.settings = settings.monitoring
        if settingsModel.timings != settings.timings { settingsModel.timings = settings.timings }
        if settingsModel.detectionMethod != settings.detection { settingsModel.detectionMethod = settings.detection }
        if settingsModel.appListOrder != settings.listOrder { settingsModel.appListOrder = settings.listOrder }
    }

    /// Shows the ignored apps in the menu, and the apps seen and ignored in
    /// Settings → Apps; never the chosen player, which doesn't pause itself,
    /// so an entry for it would do nothing.
    private func showApps() {
        let chosen = player?.bundleID
        let withoutPlayer = { (apps: [AudioSource]) in apps.filter { $0.id != chosen } }
        var shown = status
        shown.seenApps = withoutPlayer(userSettings.state.seenApps)
        shown.ignoredApps = withoutPlayer(userSettings.state.ignoredApps)
        status = shown
    }

    /// Shows how a check from Settings is going, and when updates were last
    /// checked for (every check reports here).
    private func showUpdateStatus(_ status: String) {
        settingsModel.updateStatus = status
        settingsModel.lastUpdateCheck = preferences.lastUpdateCheck
    }

    /// Shows the update settings as they are, after the user or AutoHush
    /// changed them.
    private func showUpdateSettings() {
        settingsModel.checksForUpdatesAutomatically = updates.checksAutomatically
        settingsModel.automaticUpdates = updates.mode
    }

    // MARK: - Music player

    /// Makes `bundleID` the player AutoHush controls and starts over with it.
    /// A player that isn't installed, or is chosen already, is ignored. Music
    /// that AutoHush holds paused in the previous player stays paused: the
    /// user is moving to another one. A player AutoHush must learn opens the
    /// learning window, unless another window shows the steps. A suggested
    /// web app opens "Add a Web App", filled in with its address.
    func chooseMusicPlayer(_ bundleID: String) {
        chooseMusicPlayer(bundleID, showsLearningWindow: true)
    }

    func chooseMusicPlayer(_ bundleID: String, showsLearningWindow: Bool) {
        refreshPlayerOptions()
        if let address = status.playerOptions.first(where: { $0.bundleID == bundleID })?.webAddress {
            showAddWebApp(address: address)
            return
        }
        guard bundleID != player?.bundleID,
              let chosen = players.player(bundleID: bundleID),
              let appURL = status.playerOptions.first(where: { $0.bundleID == bundleID })?.appURL
        else { return }
        logger.notice("Music player chosen: \(chosen.name, privacy: .public)")
        preferences.musicPlayer = bundleID
        session.choose(chosen)
        watchFolders(holding: appURL)
        showChosenPlayer()
        showApps()
        // From the welcome window: it goes on to what the player needs, and
        // closes once that's allowed; the learning window waits for it.
        let fromWelcome = isShowingPlayerChooser
        if fromWelcome { settingsModel.welcomeAsksPermissions = true }
        learning.follow(chosen)
        learningAfterWelcome = false
        if showsLearningWindow, case .learning = (chosen as? any LearningMusicPlayer)?.learningStatus {
            if fromWelcome { learningAfterWelcome = true } else { showLearningWindow() }
        }
        if fromWelcome { windowWatch.wake() }
    }

    /// The welcome window is done: the player is chosen and what it needs
    /// allowed (or the window was closed). A player to learn opens the
    /// learning window then.
    func finishWelcome() {
        settingsModel.welcomeAsksPermissions = false
        if isShowingPlayerChooser { playerChooser?.close() }
        guard learningAfterWelcome else { return }
        learningAfterWelcome = false
        if case .learning = status.learning { showLearningWindow() }
    }

    /// Shows how learning goes: whether it's learned in the menu and
    /// Settings, the steps and the pause in their windows; once learned, or
    /// with nothing to learn, the windows that show the steps close.
    private func showLearning(_ state: LearningSession.State) {
        let learningStatus = state.status
        let changed = learningStatus != status.learning
        var shown = status
        shown.learning = learningStatus
        shown.learningPause = state.pause
        status = shown
        guard changed, learningStatus == nil || learningStatus == .learned else { return }
        // Learned (both steps ticked), or nothing to learn: the windows go.
        let delay = learningStatus == .learned ? learnedWindowDelay : .zero
        if let window = learningWindow, window.isOpen {
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, self.status.learning == learningStatus else { return }
                window.close()
            }
        }
        if let window = addWebAppWindow, window.isOpen, case .learning = addWebAppModel.phase {
            Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, self.status.learning == learningStatus else { return }
                window.close()
            }
        }
    }

    /// Shows the chosen player in the menu and the windows.
    private func showChosenPlayer() {
        status.chosenPlayerID = player?.bundleID
        settingsModel.playerCanFade = player?.canFade ?? true
    }

    /// Checks again which players are installed, for the menu, Settings and
    /// the welcome window. While none is chosen, the status line follows. The
    /// chosen player is reported as soon as it's uninstalled, as a launch
    /// would, and controlled afresh once it's installed again.
    func refreshPlayerOptions() {
        let options = PlayerOption.list(players, locate: locateApp)
        status.playerOptions = options
        forgetDeletedWebApps(among: options)
        guard let player else {
            showSession() // waiting for a player, among these
            return
        }
        // A deleted web app can't come back as the same app (adding the site
        // again makes a new one): no player is chosen any more.
        if player.kind == .safariWebApp, !options.contains(where: { $0.bundleID == player.bundleID }),
           Self.isDeleted(player.bundleID) {
            logger.notice("\(player.name, privacy: .public) was deleted: no music player is chosen")
            forgetChosenPlayer()
            return
        }
        let appURL = options.first { $0.bundleID == player.bundleID }?.appURL
        watchFolders(holding: appURL)
        session.setPlayerInstalled(appURL != nil)
    }

    /// Watches the Applications folders, and the folder the chosen player's
    /// app is in when it's one inside them. A folder that can't be watched
    /// yet (no ~/Applications) is tried again at the next check.
    private func watchFolders(holding appURL: URL?) {
        var paths = Set(PlayerOption.applicationFolders.map(\.path))
        if let appURL { paths.insert(appURL.deletingLastPathComponent().path) }
        for path in folderWatches.keys where !paths.contains(path) {
            folderWatches[path] = nil
        }
        for path in paths where folderWatches[path] == nil {
            let folder = URL(filePath: path, directoryHint: .isDirectory)
            guard let watch = watchFolder(folder, { [weak self] in self?.checkInstalledPlayersSoon() }) else { continue }
            folderWatches[path] = watch
            logger.debug("Watching \(path, privacy: .public) for installed music players")
        }
    }

    /// Whether the app is deleted: macOS doesn't know it, or only in the Trash.
    private static func isDeleted(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return true }
        return url.pathComponents.contains(".Trash")
    }

    /// No player is chosen any more: the status line asks for one.
    private func forgetChosenPlayer() {
        preferences.musicPlayer = nil
        session.choose(nil)
        showChosenPlayer()
        learning.follow(nil)
    }

    /// Forgets the learned buttons of web apps that are gone: deleted, not
    /// just moved (macOS still knows those, the Trash included). Adding a site
    /// again makes a new web app, with a new ID.
    private func forgetDeletedWebApps(among options: [PlayerOption]) {
        let installed = Set(options.filter { $0.kind == .safariWebApp && $0.isInstalled }.map(\.bundleID))
        preferences.forgetWebAppButtons { id in
            !installed.contains(id) && NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) == nil
        }
    }

    /// Checks the players again once a change in a watched folder settles
    /// (a move, an update swapping the app) and Launch Services catches up;
    /// a later change starts the wait over.
    private func checkInstalledPlayersSoon() {
        installCheck?.cancel()
        installCheck = Task { [weak self, installCheckDelay] in
            try? await Task.sleep(for: installCheckDelay)
            guard !Task.isCancelled else { return }
            self?.refreshPlayerOptions()
        }
    }

    /// The welcome window, which asks for the music player.
    private func showPlayerChooser() {
        if playerChooser == nil {
            playerChooser = makePlayerChooser(settingsModel)
        }
        settingsModel.welcomeAsksPermissions = false
        refreshPlayerOptions()
        playerChooser?.show()
        windowWatch.wake()
    }

    /// Whether the welcome window is on screen.
    var isShowingPlayerChooser: Bool { playerChooser?.isOpen == true }

    /// The menu opens: what it lists is brought up to date. The welcome
    /// window, still open, comes forward to the desktop the user is on:
    /// another app may have covered it, or taken the user to another desktop,
    /// since it opened.
    func menuWillOpen() {
        refreshPlayerOptions()
        session.checkAccess()
        if isShowingPlayerChooser { playerChooser?.bringForward() }
    }

    // MARK: - Player relaunch

    private func registerPlayerLaunchObserver() {
        guard playerLaunchObserver == nil else { return }
        playerLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Extract the Sendable String before crossing the actor boundary.
            let bundleIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor [weak self] in
                self?.handleApplicationDidLaunch(bundleIdentifier: bundleIdentifier)
            }
        }
    }

    /// A supported player opened: it is installed now. While none is chosen,
    /// the welcome window asks again; the chosen one is controlled afresh.
    func handleApplicationDidLaunch(bundleIdentifier: String?) {
        guard let bundleIdentifier, players.player(bundleID: bundleIdentifier) != nil else { return }
        refreshPlayerOptions()
        guard player != nil else {
            showPlayerChooser()
            return
        }
        session.playerLaunched(bundleIdentifier)
    }

    /// The Mac going to sleep and waking up, for the player session (see
    /// `PlayerSession.setAsleep`). The screens waking count as awake too, so
    /// a wake macOS didn't announce can't leave AutoHush deciding nothing.
    private func registerSleepObservers() {
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false),
            (NSWorkspace.screensDidWakeNotification, false),
        ].map { name, asleep in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.session.setAsleep(asleep) }
            }
        }
    }

    private func unregisterPlayerLaunchObserver() {
        guard let playerLaunchObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(playerLaunchObserver)
        self.playerLaunchObserver = nil
    }

    // MARK: - Menu actions

    func openSettings(page: SettingsWindowController.Page? = nil) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show(page: page)
        refreshPlayerOptions()
        windowWatch.wake()
    }

    /// What each window shows that the window watch follows while it's open
    /// (Settings counts as open minimized too). macOS doesn't announce a
    /// change to these: notifications turned on or off, or reset, in System
    /// Settings (a reset is asked about again), the players installed, a
    /// permission allowed (a window waiting for one goes on by itself).
    private func registerWatchedWindows() {
        windowWatch.register(isOpen: { [weak self] in self?.settingsWindowController?.window?.isOpen == true }) { [weak self] in
            var needs: Set<WindowWatch.Refresh> = [.players, .notifications, .launchAtLogin, .permissions]
            if self?.settingsWindowController?.shownPage == .diagnostics { needs.insert(.diagnostics) }
            return needs
        }
        windowWatch.register(isOpen: { [weak self] in self?.isShowingPlayerChooser == true }) {
            [.players, .notifications, .permissions]
        }
        windowWatch.register(isOpen: { [weak self] in self?.learningWindow?.isOpen == true }) { [.permissions] }
        windowWatch.register(isOpen: { [weak self] in self?.addWebAppWindow?.isOpen == true }) { [.permissions] }
    }

    /// One of the window watch's refreshes.
    private func refresh(_ need: WindowWatch.Refresh) async {
        switch need {
        case .players:
            refreshPlayerOptions()
        case .diagnostics:
            refreshDiagnostics()
        case .notifications:
            let off = await updates.followNotificationPermission() == .off
            if settingsModel.notificationsOff != off { settingsModel.notificationsOff = off }
        case .launchAtLogin:
            settingsModel.refreshLaunchAtLogin()
        case .permissions:
            await refreshPermissions()
        }
    }

    /// The welcome window closed while it asked for the permissions: done,
    /// as with its Done button.
    func followWelcomeClosed() {
        if settingsModel.welcomeAsksPermissions, !isShowingPlayerChooser { finishWelcome() }
    }

    // MARK: - Permissions (the rest in AppDelegate+Permissions)

    /// The user went to allow Audio Recording in System Settings: macOS
    /// applies it only from the next launch, so the menu offers to reopen.
    func noteAudioRecordingAllowedInSettings() {
        status.awaitsReopenForAudioRecording = true
    }

    /// The info button after the card's line: why the player couldn't be
    /// controlled (also in Settings → Diagnostics, as "Last error").
    func showControlError() {
        guard let alert = status.controlErrorAlert else { return }
        InfoAlert.show(alert.title, alert.message)
    }

    // MARK: - Updates

    /// Quits so that the installed update opens; a pause AutoHush is holding
    /// is handed over (see `applicationShouldTerminate`).
    private func quitToFinishUpdate() {
        quitFromRunLoop()
    }

    /// Quits from the run loop, not from inside a main-actor job (the install's
    /// task, a signal handler): quitting waits for main-actor work (restoring
    /// the volume), which can't run while a main-actor job is still under way.
    private func quitFromRunLoop() {
        RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    }

    /// Quits normally on SIGTERM (from an AutoHush opened after this one,
    /// `kill`, or the system) instead of stopping at once, so the volume is
    /// restored and a pause handed over.
    private func quitOnTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.quitFromRunLoop() }
        }
        source.resume()
        terminationSignal = source
    }

    /// A moment when AutoHush can restart for an update unnoticed: it isn't
    /// holding the music paused (the new version would take that pause over,
    /// but there is no need to rely on it), and none of its menus, windows or
    /// alerts is open.
    private var isQuietMoment: Bool {
        !session.isHoldingPause
            && statusMenu?.isMenuOpen != true
            && !NSApplication.shared.windows.contains { $0.isOpen && $0.canBecomeKey }
    }
}

// MARK: - What only AppDelegate does

extension AppDelegate: AppActions {
    func openAddWebApp() { showAddWebApp() }
    func reopenAutoHush() { reopen() }
    func openNotificationSettings() { SystemSettingsPane.notifications.open() }
    func quit() { NSApp.terminate(nil) }
}
