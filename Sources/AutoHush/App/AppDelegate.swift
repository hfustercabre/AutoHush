import AppKit
import OSLog

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
    let updateChecker: UpdateChecker
    /// The music player AutoHush pauses and resumes.
    let player: any MusicPlayer
    let currentVersion: AppVersion?
    var updateCheckTimer: Timer?
    private var playerLaunchObserver: (any NSObjectProtocol)?
    private let logger = Logger(category: "AppDelegate")
    /// Replaces the real bootstrap in tests, so they never script the music player or
    /// tap real audio processes.
    private let bootstrapOverride: (@MainActor () -> Void)?

    init(
        preferences: Preferences = Preferences(),
        launchAtLoginController: any LaunchAtLoginControlling = LaunchAtLoginController(),
        updateChecker: UpdateChecker = UpdateChecker(),
        player: any MusicPlayer = SpotifyPlayer(),
        currentVersion: AppVersion? = .current,
        bootstrapOverride: (@MainActor () -> Void)? = nil
    ) {
        self.preferences = preferences
        self.updateChecker = updateChecker
        self.player = player
        self.currentVersion = currentVersion
        self.bootstrapOverride = bootstrapOverride
        super.init()
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
                checkForUpdates: { [weak self] in self?.checkForUpdatesFromUser() }
            )
        )
        settingsModel.timings = preferences.timings
        settingsModel.detectionMethod = preferences.detectionMethod
        settingsModel.checksForUpdatesAutomatically = preferences.checksForUpdatesAutomatically
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
                resolveWarning: { warning in
                    switch warning {
                    case .automationAccess:     SystemSettingsPane.automation.open()
                    case .audioRecordingAccess: SystemSettingsPane.audioCapture.open()
                    }
                },
                retry: { [weak self] in self?.retry() },
                openSettings: { [weak self] in self?.openSettings() },
                showDiagnostics: { [weak self] in self?.showDiagnostics() },
                showAvailableUpdate: { [weak self] in self?.presentAvailableUpdate() },
                checkForUpdates: { [weak self] in self?.checkForUpdatesFromUser() },
                showAbout: { [weak self] in self?.showAbout() },
                quit: { NSApp.terminate(nil) }
            )
        )
        registerPlayerLaunchObserver()
        requestBootstrap()
        scheduleAutomaticUpdateChecks()
    }

    /// Waits (briefly) for a fade in progress to give the player its volume
    /// back, so quitting never leaves the music faded down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pipeline else { return .terminateNow }
        self.pipeline = nil
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await pipeline.stopAndRestoreVolume()
            reply()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { reply() } // never hang the quit
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

    func setAvailableUpdate(_ release: AppRelease?) {
        status.availableUpdate = release
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
        pipeline?.setConfiguration(AppConfiguration(timings: preferences.timings))
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

    private func syncSettingsApps() {
        settingsModel.setApps(seen: preferences.seenApps, ignored: preferences.ignoredApps)
    }

    /// Derives the effective auto-pause state from the preferences, shows it,
    /// passes it to the pipeline and schedules the end of a snooze.
    private func applyAutoPause(now: Date = Date()) {
        let setting = preferences.autoPause.clearingExpiredSnooze(at: now)
        if setting != preferences.autoPause { preferences.autoPause = setting }

        snoozeTimer?.invalidate()
        snoozeTimer = nil
        if !setting.isEnabled {
            status.autoPause = .off
            settingsModel.autoPauseNote = nil
        } else if let until = setting.snoozedUntil {
            let description = AutoPauseSnooze.describeEnd(until, now: now)
            status.autoPause = .snoozed(until: description)
            settingsModel.autoPauseNote = "Turned off until \(description)."
            let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyAutoPause() }
            }
            RunLoop.main.add(timer, forMode: .common)
            snoozeTimer = timer
        } else {
            status.autoPause = .on
            settingsModel.autoPauseNote = nil
        }
        settingsModel.isAutoPauseOn = status.autoPause == .on
        pipeline?.setAutoPauseEnabled(setting.isActive(at: now))
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
        switch error as? AutoHushError {
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
            configuration: AppConfiguration(timings: preferences.timings),
            autoPauseEnabled: preferences.autoPause.isActive(at: Date()),
            ignoredSourceIDs: Set(preferences.ignoredApps.map(\.id)),
            detectionMethod: preferences.detectionMethod,
            announcingSourceIDs: preferences.announcingApps
        ) { [weak self] update in
            self?.apply(update)
        }
        self.pipeline = pipeline
        status.detection = .pending
        await pipeline.start()
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
    }

    private func showAbout() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph,
        ]
        let credits = NSMutableAttributedString(
            string: "Pauses your music while other apps play audio, and resumes it afterwards. Works with \(player.name).\n",
            attributes: body
        )
        var link = body
        link[.link] = URL(string: "https://github.com/\(UpdateChecker.repository)")!
        credits.append(NSAttributedString(string: "github.com/\(UpdateChecker.repository)", attributes: link))

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func showDiagnostics() {
        let lines = pipeline?.activeAudioReport() ?? []
        let sources = lines.isEmpty ? "No foreign audio output currently detected." : lines.joined(separator: "\n")
        let body = [
            sources,
            status.detection.statusLine + (preferences.detectionMethod == .audioLevels ? "" : " — AntiDot mode"),
            "Auto-pause: \(autoPauseDescription)",
            "Ignored apps: \(status.ignoredApps.isEmpty ? "none" : status.ignoredApps.map(\.name).joined(separator: ", "))",
        ].joined(separator: "\n\n")
        logger.debug("[diag] active audio: \(lines.joined(separator: "; "), privacy: .public)")
        showAlert("AutoHush Diagnostics", body)
    }

    func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }

    private var autoPauseDescription: String {
        switch status.autoPause {
        case .on:                return "on"
        case .off:               return "off"
        case .snoozed(let until): return "off until \(until)"
        }
    }

    private func retry() {
        setHealth(.starting)
        requestBootstrap()
    }
}
