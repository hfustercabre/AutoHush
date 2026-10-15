import AppKit
import AutoHushKit
import AutoHushPlayers
import CheckedPlayers

/// Adding an app through a check ("Add an App…"): its window, the warning
/// before the check, the check's panel, and keeping what worked.
extension AppDelegate {
    /// The "Add an App" window, from its first step unless it's open.
    func showAddApp() {
        let model = addAppModel ?? AddAppModel(services: liveAddAppServices())
        addAppModel = model
        if addAppWindow == nil { addAppWindow = AddAppWindowController(model: model) }
        model.services.antiDot = { [weak self] in self?.preferences.detectionMethod != .audioLevels }
        if addAppWindow?.isOpen != true { model.reset() }
        addAppWindow?.show()
    }

    private func liveAddAppServices() -> AddAppServices {
        let helper = PlayerCheckHelper.bundled
        if helper == nil { logger.error("Add an App: the check's helper is missing from the app") }
        return AddAppServices(
            listApps: { [weak self] in
                // The supported players aren't offered (their support is
                // AutoHush's own), nor Apple's apps that are no players.
                let supported = Set(self?.status.playerOptions.filter { $0.kind == .app }.map(\.bundleID) ?? [])
                return await CheckableApps.find(helper: helper, excluding: supported.union(SupportedPlayers.notPlayers))
            },
            appAt: { [weak self] url in
                Self.checkableApp(at: url, supported: self?.status.playerOptions.filter { $0.kind == .app } ?? [])
            },
            hasHelper: helper != nil,
            showChooser: { [weak self] in self?.showAppChooser() },
            closeChooser: { [weak self] in self?.appChooserWindow?.close() },
            traits: { CheckedAppTraits.of(appAt: $0) },
            isRunning: { NSRunningApplication.running($0) != nil },
            open: { app, withLaunchOption in
                if withLaunchOption, let helper { return await helper.reopenWithLaunchOption(app.url) }
                return await Self.openInBackground(app)
            },
            runsWithLaunchOption: { app in await helper?.runsWithLaunchOption(app.url) },
            reopen: { app in await helper?.reopenWithLaunchOption(app.url) ?? false },
            permissions: { app, scriptable in await Self.checkPermissions(app, scriptable: scriptable) },
            request: { permission, app, current in await Self.request(permission, app: app, current: current) },
            isPlaying: { [weak self] app, traits in
                // A browser's web app plays through its browser.
                let source = if case .browserWebApp(let browser)? = traits.framework { browser } else { app.bundleID }
                guard let pid = NSRunningApplication.running(source)?.processIdentifier else { return false }
                // AntiDot mode taps no sound: its level isn't measured.
                let antiDot = self?.preferences.detectionMethod != .audioLevels
                var playing = AppPlaying()
                if antiDot { playing.levelMeasured = { false } }
                return await playing.plays(pid)
            },
            startCheck: { [weak self] app, taps, onLine in
                guard let helper else { return nil }
                self?.logger.notice("Add an App: checking \(app.name, privacy: .public)\(taps ? "" : " (AntiDot mode: no audio taps)", privacy: .public)")
                return try? helper.check(app.url, taps: taps, onLine: onLine)
            },
            showWarning: { [weak self] in self?.showCheckWarning() },
            closeWarning: { [weak self] in self?.checkWarningWindow?.close() },
            checkStarted: { [weak self] app in
                guard let self, let model = self.addAppModel else { return }
                self.checkPanel.show(app, model: model)
            },
            checkEnded: { [weak self] in self?.checkPanel.hide() },
            showLog: {
                guard let log = PlayerCheckHelper.newestLog else { return }
                NSWorkspace.shared.open(log)
            },
            reopenAutoHush: { [weak self] in
                self?.noteAudioRecordingAllowedInSettings()
                self?.reopen()
            },
            use: { [weak self] result, asksToReopen in self?.useCheckedApp(result, asksToReopen: asksToReopen) },
            close: { [weak self] in self?.addAppWindow?.close() }
        )
    }

    /// The list of apps to choose (the first step's window).
    private func showAppChooser() {
        guard let model = addAppModel else { return }
        if appChooserWindow == nil { appChooserWindow = AppChooserWindowController(model: model) }
        appChooserWindow?.show()
    }

    /// An app picked on the disk (Other App…), named as the list names it,
    /// unless AutoHush supports it already (`supported`) or it's AutoHush.
    static func checkableApp(at url: URL, supported: [PlayerOption]) -> Result<CheckableApp, OtherAppProblem> {
        guard let app = CheckableApp.at(url) else { return .failure(.notAnApp) }
        if app.bundleID == Bundle.main.bundleIdentifier || app.bundleID.hasPrefix("com.autohush.") { return .failure(.autoHush) }
        if let player = supported.first(where: { $0.bundleID == app.bundleID }) { return .failure(.supported(player.name)) }
        return .success(app)
    }

    /// The warning before the check (W6), for the chosen app.
    private func showCheckWarning() {
        guard let model = addAppModel, let app = model.chosen else { return }
        checkWarningWindow?.close()
        let muted = model.permissions.audio == .allowed && !model.antiDot
        let window = CheckWarningWindowController(app: app, muted: muted) { [weak model] in model?.startCheck() }
        checkWarningWindow = window
        window.show()
    }

    /// Keeps what the check found, then makes the app the player: chosen
    /// again when it was already (checked again, its new setup is used).
    private func useCheckedApp(_ result: CheckResult, asksToReopen: Bool) {
        guard let setup = result.setup else { return }
        SupportedPlayers.checkedPlayers.keep(result)
        logger.notice("Add an App: \(setup.name, privacy: .public) added, by \(setup.ways.map(\.logName).joined(separator: ", "), privacy: .public)")
        refreshPlayerOptions()
        chooseMusicPlayer(setup.bundleID, replacing: setup.bundleID == player?.bundleID, asksToReopen: asksToReopen)
    }

    /// Opens the app without bringing it forward, and waits (up to 10 s)
    /// for it to run.
    private static func openInBackground(_ app: CheckableApp) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        guard (try? await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)) != nil else { return false }
        for _ in 0..<20 where NSRunningApplication.running(app.bundleID) == nil {
            try? await Task.sleep(for: .milliseconds(500))
        }
        return NSRunningApplication.running(app.bundleID) != nil
    }

    /// What the check of `app` needs, as it stands now.
    private static func checkPermissions(_ app: CheckableApp, scriptable: Bool) async -> CheckPermissions {
        var permissions = CheckPermissions(accessibility: AccessibilityPermission.isTrusted())
        permissions.audio = switch TCCAudioCapturePermission().status() {
        case .granted?, nil: .allowed // nil: macOS can't tell; the check finds out
        case .notDetermined?: .notAsked
        case .denied?: .denied
        }
        if scriptable {
            if let pid = NSRunningApplication.running(app.bundleID)?.processIdentifier {
                let status = await PermissionCenter.queue.run { AutomationPermission.check(pid: pid, ask: false) }
                permissions.automation = PermissionCenter.access(automationStatus: status)
            } else {
                permissions.automation = .playerNotRunning
            }
        }
        return permissions
    }

    /// A permission's Allow…: macOS's prompt when it hasn't asked yet, else
    /// System Settings; for Automation with the app closed, the app.
    private static func request(_ permission: CheckPermission, app: CheckableApp, current: CheckPermissions) async {
        switch permission {
        case .accessibility:
            _ = AccessibilityPermission.isTrusted(prompt: true)
            SystemSettingsPane.accessibility.open()
        case .audioRecording:
            if current.audio == .notAsked {
                TCCAudioCapturePermission().request { _ in }
            } else {
                SystemSettingsPane.audioCapture.open()
            }
        case .automation:
            switch current.automation {
            case .notAsked?:
                if let pid = NSRunningApplication.running(app.bundleID)?.processIdentifier {
                    _ = await PermissionCenter.queue.run { AutomationPermission.check(pid: pid, ask: true) }
                }
            case .playerNotRunning?:
                _ = await openInBackground(app)
            default:
                SystemSettingsPane.automation.open()
            }
        }
    }
}

private extension PlayerSetup.Way {
    /// How the log names it (English).
    var logName: String {
        switch self {
        case .script: "AppleScript"
        case .menu(let name): "its menu \(name)"
        case .page: "its page"
        case .panel: "the Now Playing panel"
        case .mute: "muting it"
        }
    }
}
