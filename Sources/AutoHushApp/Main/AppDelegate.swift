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
    /// The music player AutoHush pauses and resumes.
    let player: any MusicPlayer
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
    /// Other copies of AutoHush, which quit when this one opens.
    private let otherInstances: OtherInstances
    /// Turns SIGTERM into a normal quit.
    private var terminationSignal: (any DispatchSourceSignal)?

    init(
        preferences: Preferences = Preferences(),
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        updateChecker: UpdateChecker = UpdateChecker(),
        updateInstaller: any UpdateInstalling = UpdateInstaller(),
        updateNotifier: any UpdateNotifying = SystemUpdateNotifier(),
        updateDownloadsFolder: URL = UpdateDownloads.defaultFolder,
        player: any MusicPlayer = SupportedPlayers.makeDefault(),
        currentVersion: AppVersion? = .current,
        otherInstances: OtherInstances = .live(bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.autohush.AutoHush"),
        bootstrapOverride: (@MainActor () -> Void)? = nil
    ) {
        self.preferences = preferences
        self.player = player
        self.bootstrapOverride = bootstrapOverride
        self.updateNotifier = updateNotifier
        self.otherInstances = otherInstances
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
            onStatus: { [weak self] in self?.settingsModel.updateStatus = $0 }
        )
        settingsModel = SettingsModel(
            launchAtLoginController: launchAtLoginController,
            actions: .init(
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
        status.playerName = player.name
        status.ignoredApps = preferences.ignoredApps
        syncSettingsApps()
        applyAutoPause()
    }

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(
            status: status,
            actions: .init(
                toggleAutoPause: { [weak self] in self?.toggleAutoPause() },
                snooze: { [weak self] in self?.snooze($0) },
                setIgnored: { [weak self] in self?.setIgnored($0, $1) },
                resolveWarning: { $0.settingsPane.open() },
                retry: { [weak self] in self?.retry() },
                openSettings: { [weak self] in self?.openSettings() },
                showDiagnostics: { [weak self] in self?.showDiagnostics() },
                showAvailableUpdate: { [weak self] in self?.updates.presentAvailableUpdate() },
                checkForUpdates: { [weak self] in self?.updates.checkFromUser() },
                showAbout: { [weak self] in AboutPanel.show(playerName: self?.player.name ?? "") },
                quit: { NSApp.terminate(nil) }
            )
        )
        quitOnTerminationSignal()
        registerPlayerLaunchObserver()
        // Opened last, this copy is the one that runs: any other quits first,
        // handing over a pause it held, so they never both pause and resume
        // the music.
        let otherInstances = otherInstances
        Task {
            let others = await otherInstances.quitAll()
            if !others.isEmpty { logger.notice("Quit \(others.count) other running AutoHush") }
            requestBootstrap()
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
    }

    private func apply(_ update: MonitoringPipeline.StatusUpdate) {
        switch update {
        case .playback(let state):       status.playback = state
        case .activeSources(let sources):
            status.setActiveSources(sources)
            preferences.recordSeen(sources)
            syncSettingsApps()
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

    /// Stores what automatic checks lead to, and acts on an update already
    /// found the new way (e.g. downloads it).
    func setAutomaticUpdates(_ mode: AutomaticUpdates) {
        updates.mode = mode
        settingsModel.automaticUpdates = mode
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
        status.ignoredApps = preferences.ignoredApps
        pipeline?.setIgnoredSources(Set(apps.map(\.id)))
        syncSettingsApps()
    }

    /// The engine's configuration: the user's timings, and the supported
    /// players, whose own audio never counts as another app playing.
    private var currentConfiguration: AppConfiguration {
        var configuration = AppConfiguration(timings: preferences.timings)
        configuration.musicPlayerBundleIDs = SupportedPlayers.bundleIDs
        return configuration
    }

    private func syncSettingsApps() {
        settingsModel.setApps(seen: preferences.seenApps, ignored: preferences.ignoredApps)
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

    func handleApplicationDidLaunch(bundleIdentifier: String?) {
        guard bundleIdentifier == player.bundleID else { return }
        logger.debug("\(self.player.name, privacy: .public) launch detected — re-running bootstrap")
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

        do {
            try await player.verifyControlAccess()
        } catch {
            guard generation == bootstrapGeneration else { return }
            if retriesLeft > 0, Self.isTransientStartupError(error) {
                logger.debug("\(self.player.name, privacy: .public) is not ready yet (\(error.localizedDescription, privacy: .public)) — retrying")
                try? await Task.sleep(for: .seconds(Self.startupRetryDelay))
                guard generation == bootstrapGeneration else { return } // Retry or another launch took over
                await bootstrap(retriesLeft: retriesLeft - 1)
                return
            }
            logger.error("Automation preflight failed: \(error.localizedDescription, privacy: .public)")
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
        status.detection = .pending
        await pipeline.start(takingOverPause: takesOverPause())
        guard generation == bootstrapGeneration else { return }
        setHealth(.ready)
    }

    private func tearDownPipeline() {
        pipeline?.stop()
        pipeline = nil
    }

    // MARK: - Menu actions

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: settingsModel)
        }
        settingsWindowController?.show()
        Task { settingsModel.notificationsOff = await updateNotifier.notificationsAreOff() }
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
