import AppKit
import OSLog
import AutoHushKit
import AutoHushPlayers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// What the menu bar shows; rendered by `statusMenu` once it exists.
    private(set) var status = AppStatus() {
        didSet { statusMenu?.status = status }
    }

    private var statusMenu: StatusMenuController?
    private var pipeline: MonitoringPipeline?
    let preferences: Preferences
    private var snoozeTimer: Timer?
    private var bootstrapGeneration = 0
    /// The Settings window's content, kept in sync with the app's state.
    private(set) var settingsModel: SettingsModel!
    private var settingsWindowController: SettingsWindowController?
    /// Follows the notification setting and the installed players while
    /// Settings or the welcome window is open.
    private var windowsWatch: Task<Void, Never>?
    /// The music players to choose from.
    private let players: MusicPlayerCatalog
    private let locateApp: PlayerOption.Locate
    /// The music player AutoHush pauses and resumes; `nil` until one is chosen.
    private(set) var player: (any MusicPlayer)?
    /// Asks for the music player while none is chosen; made when first needed.
    private var playerChooser: (any PlayerChooserPresenting)?
    private let makePlayerChooser: @MainActor (SettingsModel) -> any PlayerChooserPresenting
    /// Update checks (menu, Settings and the daily automatic one), downloads,
    /// installs and their notifications.
    private(set) var updates: UpdateController!
    private let updateNotifier: any UpdateNotifying
    private var playerLaunchObserver: (any NSObjectProtocol)?
    private let logger = Logger(category: "AppDelegate")
    /// Replaces the real bootstrap in tests, so they never script the music player or
    /// tap real audio processes.
    private let bootstrapOverride: (@MainActor () -> Void)?
    /// The first monitoring that starts may take over a pause handed over by
    /// the AutoHush before this one; later ones don't.
    private var pauseHandoverChecked = false
    /// A restart for an update or by another copy takes seconds: an older
    /// handover is stale.
    static let pauseHandoverMaxAge: TimeInterval = 60
    /// Copies of AutoHush opened before this one, which quit when it opens.
    private let otherInstances: OtherInstances
    /// Turns SIGTERM into a normal quit.
    private var terminationSignal: (any DispatchSourceSignal)?
    /// While the player needs a permission, starting is tried again this
    /// often: macOS doesn't announce when one is granted.
    private let permissionRetryInterval: TimeInterval
    private var permissionRetry: Timer?

    init(
        preferences: Preferences = Preferences(),
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        updateChecker: UpdateChecker = UpdateChecker(),
        updateInstaller: any UpdateInstalling = UpdateInstaller(),
        updateNotifier: any UpdateNotifying = SystemUpdateNotifier(),
        updateDownloadsFolder: URL = UpdateDownloads.defaultFolder,
        players: MusicPlayerCatalog = SupportedPlayers.catalog,
        locateApp: @escaping PlayerOption.Locate = PlayerOption.locateInstalledApp,
        makePlayerChooser: @escaping @MainActor (SettingsModel) -> any PlayerChooserPresenting = {
            PlayerChooserWindowController(model: $0)
        },
        currentVersion: AppVersion? = .current,
        otherInstances: OtherInstances = .live(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.autohush.AutoHush"),
        permissionRetryInterval: TimeInterval = 3,
        bootstrapOverride: (@MainActor () -> Void)? = nil
    ) {
        self.preferences = preferences
        self.players = players
        self.locateApp = locateApp
        self.makePlayerChooser = makePlayerChooser
        // Before anything else is stored: people updating keep their player.
        preferences.keepFormerPlayer(players.formerDefault)
        self.player = players.player(bundleID: preferences.musicPlayer)
        self.bootstrapOverride = bootstrapOverride
        self.updateNotifier = updateNotifier
        self.otherInstances = otherInstances
        self.permissionRetryInterval = permissionRetryInterval
        super.init()
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
            launchAtLoginController: launchAtLoginController,
            actions: .init(
                chooseMusicPlayer: { [weak self] in self?.chooseMusicPlayer($0) },
                setAutoPause: { [weak self] in self?.setAutoPause($0) },
                setIgnored: { [weak self] in self?.setIgnored($0, $1) },
                forgetApp: { [weak self] in self?.forget($0) },
                forgetAllApps: { [weak self] in self?.forgetAllApps() },
                setTimings: { [weak self] in self?.setTimings($0) },
                setDetectionMethod: { [weak self] in self?.setDetectionMethod($0) },
                setChecksForUpdates: { [weak self] in self?.setChecksForUpdatesAutomatically($0) },
                setAutomaticUpdates: { [weak self] in self?.setAutomaticUpdates($0) },
                checkForUpdates: { [weak self] in self?.updates.checkFromUser() },
                openNotificationSettings: { SystemSettingsPane.notifications.open() }
            )
        )
        settingsModel.timings = preferences.timings
        settingsModel.detectionMethod = preferences.detectionMethod
        settingsModel.checksForUpdatesAutomatically = preferences.checksForUpdatesAutomatically
        settingsModel.automaticUpdates = preferences.automaticUpdates
        settingsModel.updateInstallNote = updates.installUnavailability?.explanation
        settingsModel.currentVersion = currentVersion?.description
        settingsModel.lastUpdateCheck = preferences.lastUpdateCheck
        showChosenPlayer()
        refreshPlayerOptions()
        showApps()
        applyAutoPause()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(
            status: status,
            actions: .init(
                toggleAutoPause: { [weak self] in self?.toggleAutoPause() },
                snooze: { [weak self] in self?.snooze($0) },
                chooseMusicPlayer: { [weak self] in self?.chooseMusicPlayer($0) },
                menuWillOpen: { [weak self] in self?.refreshPlayerOptions() },
                setIgnored: { [weak self] in self?.setIgnored($0, $1) },
                resolveWarning: { $0.settingsPane.open() },
                retry: { [weak self] in self?.retry() },
                openSettings: { [weak self] in self?.openSettings() },
                showDiagnostics: { [weak self] in self?.showDiagnostics() },
                showAvailableUpdate: { [weak self] in self?.updates.presentAvailableUpdate() },
                checkForUpdates: { [weak self] in self?.updates.checkFromUser() },
                showAbout: { [weak self] in AboutPanel.show(playerNames: self?.players.players.map(\.name) ?? []) },
                quit: { NSApp.terminate(nil) }
            )
        )
        quitOnTerminationSignal()
        registerPlayerLaunchObserver()
        // Opened last, this copy is the one that runs: any opened before it
        // quits first, handing over a pause it held, so they never both pause
        // and resume the music.
        let otherInstances = otherInstances
        Task {
            let others = await otherInstances.quitAll()
            if !others.isEmpty { logger.notice("Quit \(others.count) other running AutoHush") }
            if player == nil {
                showPlayerChooser()
            } else {
                requestBootstrap()
            }
        }
        updates.noteLaunch()
        updates.scheduleAutomaticChecks()
    }

    /// Waits (briefly) for a fade in progress to give the player its volume
    /// back, so quitting never leaves the music faded down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A pause AutoHush is holding is handed over: an AutoHush opened next
        // (an update, another copy, a quick reopen) resumes the music once the
        // other apps stop. Later than `pauseHandoverMaxAge`, it's ignored.
        if status.playback == .pausedByMonitor { preferences.pauseHandedOverAt = Date() }
        guard let pipeline else { return .terminateNow }
        self.pipeline = nil
        var replied = false
        let reply: @MainActor () -> Void = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await pipeline.stopAndRestoreVolume()
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
        tearDownPipeline()
    }

    // MARK: - Status

    func setHealth(_ health: AppHealthState) {
        status.setHealth(health)
        followPermission()
    }

    /// While the player needs a permission, tries starting again every
    /// `permissionRetryInterval`, so AutoHush starts as soon as it's granted.
    private func followPermission() {
        guard case .needsPermission = status.health else {
            permissionRetry?.invalidate()
            permissionRetry = nil
            return
        }
        guard permissionRetry == nil else { return }
        let timer = Timer(timeInterval: permissionRetryInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.permissionRetry = nil
                guard case .needsPermission = self.status.health else { return }
                self.requestBootstrap()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionRetry = timer
    }

    func apply(_ update: MonitoringPipeline.StatusUpdate) {
        switch update {
        case .playback(let state):       status.playback = state
        case .activeSources(let sources):
            status.setActiveSources(sources)
            preferences.recordSeen(sources)
            showApps()
        case .detection(let mode):       status.detection = mode
        case .announcingApp(let id):     preferences.announcingApps.insert(id)
        }
    }

    // MARK: - Auto-pause and ignored apps

    func toggleAutoPause(now: Date = Date()) {
        let isActive = preferences.autoPause.isActive(at: now)
        // Turning it on also ends a snooze; turning it off is indefinite.
        preferences.autoPause = AutoPauseSetting(isEnabled: !isActive, snoozedUntil: nil)
        applyAutoPause(now: now)
    }

    func snooze(_ snooze: AutoPauseSnooze, now: Date = Date()) {
        preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: snooze.endDate(from: now))
        applyAutoPause(now: now)
    }

    func setAutoPause(_ on: Bool) {
        preferences.autoPause = AutoPauseSetting(isEnabled: on, snoozedUntil: nil)
        applyAutoPause()
    }

    func setIgnored(_ source: AudioSource, _ ignored: Bool) {
        // Keep the app (with its icon) listed in Settings → Apps.
        if source.bundlePath != nil { preferences.recordSeen([source]) }
        var apps = preferences.ignoredApps.filter { $0.id != source.id }
        if ignored { apps.append(AudioSource(id: source.id, name: source.name)) }
        applyIgnoredApps(apps)
    }

    /// Removes an app from Settings → Apps; a forgotten app is no longer ignored.
    func forget(_ source: AudioSource) {
        preferences.seenApps.removeAll { $0.id == source.id }
        applyIgnoredApps(preferences.ignoredApps.filter { $0.id != source.id })
    }

    /// Empties Settings → Apps: every app is forgotten and none is ignored
    /// any more. Apps reappear as they play audio.
    func forgetAllApps() {
        preferences.seenApps = []
        applyIgnoredApps([])
    }

    func setTimings(_ timings: TimingSettings) {
        preferences.timings = timings
        settingsModel.timings = preferences.timings
        pipeline?.setConfiguration(currentConfiguration)
    }

    func setChecksForUpdatesAutomatically(_ enabled: Bool) {
        updates.checksAutomatically = enabled
        settingsModel.checksForUpdatesAutomatically = enabled
        if enabled { Task { await updates.runAutomaticTasks() } }
    }

    /// Shows how a check from Settings is going, and when updates were last
    /// checked for (every check reports here).
    private func showUpdateStatus(_ status: String) {
        settingsModel.updateStatus = status
        settingsModel.lastUpdateCheck = preferences.lastUpdateCheck
    }

    /// Shows the update settings as they are, after AutoHush changed them.
    private func showUpdateSettings() {
        settingsModel.checksForUpdatesAutomatically = updates.checksAutomatically
        settingsModel.automaticUpdates = updates.mode
    }

    /// Stores what automatic checks lead to, and acts on an update already
    /// found the new way (e.g. downloads it). A choice that notifies asks for
    /// permission to, if the user hasn't answered yet.
    func setAutomaticUpdates(_ mode: AutomaticUpdates) {
        updates.mode = mode
        settingsModel.automaticUpdates = mode
        if mode != .install { updateNotifier.requestPermission() }
        Task { await updates.runAutomaticTasks() }
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        preferences.detectionMethod = method
        settingsModel.detectionMethod = method
        pipeline?.setDetectionMethod(method)
    }

    /// Stores the ignored apps and passes them to the menu, the monitor and Settings.
    private func applyIgnoredApps(_ apps: [AudioSource]) {
        preferences.ignoredApps = apps
        pipeline?.setIgnoredSources(Set(apps.map(\.id)))
        showApps()
    }

    /// The engine's configuration: the user's timings, and the chosen player,
    /// whose own audio never counts as another app playing.
    var currentConfiguration: AppConfiguration {
        var configuration = AppConfiguration(timings: preferences.timings)
        configuration.musicPlayerBundleID = player?.bundleID
        return configuration
    }

    /// Shows the ignored apps in the menu, and the apps seen and ignored in
    /// Settings → Apps; never the chosen player, which doesn't pause itself,
    /// so an entry for it would do nothing.
    private func showApps() {
        let chosen = player?.bundleID
        let withoutPlayer = { (apps: [AudioSource]) in apps.filter { $0.id != chosen } }
        status.ignoredApps = withoutPlayer(preferences.ignoredApps)
        settingsModel.setApps(seen: withoutPlayer(preferences.seenApps), ignored: withoutPlayer(preferences.ignoredApps))
    }

    /// Derives the effective auto-pause state from the preferences, shows it,
    /// passes it to the pipeline and schedules its next change.
    private func applyAutoPause(now: Date = Date()) {
        let setting = preferences.autoPause.clearingExpiredSnooze(at: now)
        if setting != preferences.autoPause { preferences.autoPause = setting }

        status.autoPause = AppStatus.AutoPause(setting, now: now)
        settingsModel.isAutoPauseOn = status.autoPause == .on
        settingsModel.autoPauseNote = status.autoPause.settingsNote
        let snoozeEnd = setting.isEnabled ? setting.snoozedUntil : nil
        scheduleAutoPauseUpdate(at: snoozeEnd.map { AppStatus.AutoPause.nextChange(snoozedUntil: $0, now: now) })
        pipeline?.setAutoPauseEnabled(setting.isActive(at: now))
    }

    /// Applies auto-pause again at `date`: when the snooze ends, or at midnight
    /// so the menu's "until tomorrow 8:00" becomes "until 8:00" (`nil`: no snooze).
    private func scheduleAutoPauseUpdate(at date: Date?) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAutoPause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    // MARK: - Music player

    /// Makes `bundleID` the player AutoHush controls and starts over with it.
    /// A player that isn't installed, or is chosen already, is ignored. Music
    /// that AutoHush holds paused in the previous player stays paused: the
    /// user is moving to another one.
    func chooseMusicPlayer(_ bundleID: String) {
        refreshPlayerOptions()
        guard bundleID != player?.bundleID,
              let chosen = players.player(bundleID: bundleID),
              status.playerOptions.contains(where: { $0.bundleID == bundleID && $0.isInstalled })
        else { return }
        logger.notice("Music player chosen: \(chosen.name, privacy: .public)")
        preferences.musicPlayer = bundleID
        player = chosen
        showChosenPlayer()
        showApps()
        playerChooser?.close()
        setHealth(.starting)
        requestBootstrap()
    }

    /// Shows the chosen player in the menu and Settings.
    private func showChosenPlayer() {
        status.chosenPlayerID = player?.bundleID
        settingsModel.chosenPlayerID = player?.bundleID
        settingsModel.playerCanFade = player?.canFade ?? true
    }

    /// Checks again which players are installed, for the menu, Settings and
    /// the welcome window. While none is chosen, the status line follows; a
    /// chosen player found installed again is controlled afresh.
    func refreshPlayerOptions() {
        let options = PlayerOption.list(players, locate: locateApp)
        if status.playerOptions != options { status.playerOptions = options }
        if settingsModel.playerOptions != options { settingsModel.playerOptions = options }
        guard let player else {
            setHealth(.waitingForPlayer(among: options))
            return
        }
        if status.health == .playerNotInstalled(player.name),
           options.contains(where: { $0.bundleID == player.bundleID && $0.isInstalled }) {
            retry()
        }
    }

    /// The welcome window, which asks for the music player.
    private func showPlayerChooser() {
        if playerChooser == nil {
            playerChooser = makePlayerChooser(settingsModel)
        }
        refreshPlayerOptions()
        playerChooser?.show()
        watchWindows()
    }

    /// Whether the welcome window is on screen.
    var isShowingPlayerChooser: Bool { playerChooser?.isVisible == true }

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
        guard let player else {
            showPlayerChooser()
            return
        }
        guard bundleIdentifier == player.bundleID else { return }
        logger.debug("\(player.name, privacy: .public) launch detected — re-running bootstrap")
        setHealth(.starting)
        // The player may not answer yet while it finishes starting up.
        requestBootstrap(retries: Self.startupRetries)
    }

    private func unregisterPlayerLaunchObserver() {
        guard let playerLaunchObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(playerLaunchObserver)
        self.playerLaunchObserver = nil
    }

    // MARK: - Bootstrap

    /// Startup checks after the player launches are retried this often, this
    /// far apart, while it is not ready to answer.
    static let startupRetries = 3
    static let startupRetryDelay: TimeInterval = 2

    private func requestBootstrap(retries: Int = 0) {
        if let bootstrapOverride {
            bootstrapOverride()
            return
        }
        Task { await bootstrap(retriesLeft: retries) }
    }

    /// Errors that mean the player is not ready yet rather than a lasting problem.
    nonisolated static func isTransientStartupError(_ error: any Error) -> Bool {
        switch error as? MusicPlayerError {
        case .playerNotResponding, .playerNotRunning: return true
        default:                                         return false
        }
    }

    private func bootstrap(retriesLeft: Int = 0) async {
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        tearDownPipeline()
        guard let player else {
            setHealth(.waitingForPlayer(among: status.playerOptions)) // nothing to control yet
            return
        }
        guard locateApp(player.bundleID) != nil else {
            setHealth(.playerNotInstalled(player.name))
            return
        }

        do {
            try await player.verifyControlAccess()
        } catch {
            guard generation == bootstrapGeneration else { return }
            if retriesLeft > 0, Self.isTransientStartupError(error) {
                logger.debug("\(player.name, privacy: .public) is not ready yet (\(error.localizedDescription, privacy: .public)) — retrying")
                try? await Task.sleep(for: .seconds(Self.startupRetryDelay))
                guard generation == bootstrapGeneration else { return } // Retry or another launch took over
                await bootstrap(retriesLeft: retriesLeft - 1)
                return
            }
            logger.error("Can't control \(player.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            setHealth(AppHealthState(startupError: error, playerName: player.name))
            return
        }
        // A newer bootstrap (Retry, player relaunch) started while we awaited.
        guard generation == bootstrapGeneration else { return }

        let pipeline = MonitoringPipeline(
            player: player,
            configuration: currentConfiguration,
            autoPauseEnabled: preferences.autoPause.isActive(at: Date()),
            ignoredSourceIDs: Set(preferences.ignoredApps.map(\.id)),
            detectionMethod: preferences.detectionMethod,
            announcingSourceIDs: preferences.announcingApps
        ) { [weak self] update in
            self?.apply(update)
        }
        self.pipeline = pipeline
        await pipeline.start(takingOverPause: takesOverPause())
        guard generation == bootstrapGeneration else { return }
        setHealth(.ready)
    }

    /// Without a pipeline nothing is known about the music: a state it left
    /// behind would otherwise hand over a pause that no longer exists, or
    /// keep automatic updates from ever finding a quiet moment.
    private func tearDownPipeline() {
        pipeline?.stop()
        pipeline = nil
        status.playback = .unknown
        status.detection = .pending
    }

    // MARK: - Menu actions

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show()
        refreshPlayerOptions()
        watchWindows()
    }

    /// While Settings or the welcome window is open, checks every second
    /// whether the user turned AutoHush's notifications on or off, or reset
    /// them, in System Settings, and which music players are installed, so
    /// the windows follow at once and a reset is asked about again. macOS
    /// doesn't announce these changes.
    private func watchWindows() {
        windowsWatch?.cancel()
        windowsWatch = Task { [weak self] in
            while !Task.isCancelled, let self,
                  self.settingsWindowController?.window?.isVisible == true || self.isShowingPlayerChooser {
                self.refreshPlayerOptions()
                let off = await self.updates.followNotificationPermission() == .off
                if self.settingsModel.notificationsOff != off { self.settingsModel.notificationsOff = off }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func showDiagnostics() {
        let report = DiagnosticsReport.text(
            activeAudio: pipeline?.activeAudioReport() ?? [], status: status, detectionMethod: preferences.detectionMethod
        )
        logger.debug("[diag] \(report, privacy: .public)")
        InfoAlert.show(String(localized: "AutoHush Diagnostics", comment: "Title of the Diagnostics alert"), report)
    }

    private func retry() {
        setHealth(.starting)
        requestBootstrap()
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

    /// Whether monitoring takes over a pause handed over by the AutoHush before
    /// this one, at most `pauseHandoverMaxAge` before `now`. Only the first
    /// monitoring asks; it starts after other copies have quit, so their
    /// handover is in by then.
    func takesOverPause(now: Date = Date()) -> Bool {
        guard !pauseHandoverChecked else { return false }
        pauseHandoverChecked = true
        guard let handedOver = preferences.pauseHandedOverAt else { return false }
        preferences.pauseHandedOverAt = nil
        return (0...Self.pauseHandoverMaxAge).contains(now.timeIntervalSince(handedOver))
    }

    /// A moment when AutoHush can restart for an update unnoticed: it isn't
    /// holding the music paused (the new version would take that pause over,
    /// but there is no need to rely on it), and none of its menus, windows or
    /// alerts is open.
    private var isQuietMoment: Bool {
        status.playback != .pausedByMonitor
            && statusMenu?.isMenuOpen != true
            && !NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeKey }
    }
}
