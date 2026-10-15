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
            appAt: { [weak self] url in self?.checkableApp(at: url) ?? .failure(.notAnApp) },
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
            isPlaying: { app, traits in
                // A browser's web app plays through its browser.
                let source = if case .browserWebApp(let browser)? = traits.framework { browser } else { app.bundleID }
                guard let pid = NSRunningApplication.running(source)?.processIdentifier else { return false }
                return await AppPlaying().plays(pid)
            },
            startCheck: { [weak self] app, onLine in
                guard let helper else { return nil }
                self?.logger.notice("Add an App: checking \(app.name, privacy: .public)")
                return try? helper.check(app.url, onLine: onLine)
            },
            showWarning: { [weak self] in self?.showCheckWarning() },
            checkStarted: { [weak self] app in
                guard let self, let model = self.addAppModel else { return }
                self.checkPanel.show(app, model: model)
            },
            checkEnded: { [weak self] in self?.checkPanel.hide() },
            use: { [weak self] result in self?.useCheckedApp(result) },
            close: { [weak self] in self?.addAppWindow?.close() }
        )
    }

    /// The list of apps to choose (the first step's window).
    private func showAppChooser() {
        guard let model = addAppModel else { return }
        if appChooserWindow == nil { appChooserWindow = AppChooserWindowController(model: model) }
        appChooserWindow?.show()
    }

    /// An app picked on the disk (Other App…), unless AutoHush supports it
    /// already or it's AutoHush.
    private func checkableApp(at url: URL) -> Result<CheckableApp, OtherAppProblem> {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, url.pathExtension == "app" else { return .failure(.notAnApp) }
        if id == Bundle.main.bundleIdentifier || id.hasPrefix("com.autohush.") { return .failure(.autoHush) }
        if let supported = status.playerOptions.first(where: { $0.kind == .app && $0.bundleID == id }) {
            return .failure(.supported(supported.name))
        }
        return .success(CheckableApp(bundleID: id, name: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                                     url: url, browserName: CheckableApp.browserName(ofAppAt: url)))
    }

    /// The warning before the check (W6), for the chosen app.
    private func showCheckWarning() {
        guard let model = addAppModel, let app = model.chosen else { return }
        checkWarningWindow?.close()
        let window = CheckWarningWindowController(app: app) { [weak model] in model?.startCheck() }
        checkWarningWindow = window
        window.show()
    }

    /// Keeps what the check found, then makes the app the player.
    private func useCheckedApp(_ result: CheckResult) {
        guard let setup = result.setup else { return }
        SupportedPlayers.checkedPlayers.keep(result)
        logger.notice("Add an App: \(setup.name, privacy: .public) added, by \(setup.ways.map(\.logName).joined(separator: ", "), privacy: .public)")
        refreshPlayerOptions()
        chooseMusicPlayer(setup.bundleID)
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
