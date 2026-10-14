import AppKit
import OSLog
import AutoHushKit

// UpdateController: launch and the daily checks.
extension UpdateController {
    /// At launch: listens for clicks on notifications, asks for permission to
    /// send them (on the first launch, as automatic checks start on), says so
    /// when AutoHush was updated since it last ran, and tidies a kept download.
    func noteLaunch() {
        notifier.activate()
        if checksAutomatically { notifier.requestPermission() }
        if let currentVersion {
            let last = preferences.lastLaunchedVersion.flatMap(AppVersion.init)
            preferences.lastLaunchedVersion = currentVersion.description
            if let last, last < currentVersion { announce(.installed(currentVersion)) }
        }
        tidy()
    }

    /// Runs the automatic work shortly after launch, then hourly.
    func scheduleAutomaticChecks() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runAutomaticTasks() }
        }
        timer.fireDate = Date().addingTimeInterval(30) // let the network come up after login
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func isCheckDue(now date: Date? = nil) -> Bool {
        guard checksAutomatically else { return false }
        guard let last = preferences.lastUpdateCheck else { return true }
        return (date ?? now()).timeIntervalSince(last) >= Self.automaticCheckInterval
    }

    /// Tidies a kept download, checks when a check is due, then acts on what
    /// it (or an earlier check) found, as the user chose. Whatever has to
    /// wait (a quiet moment, the network) is tried again at the next run.
    func runAutomaticTasks() async {
        await followNotificationPermission()
        tidy()
        if isCheckDue() { await check(userInitiated: false) }
        await followUp()
    }

    private func followUp() async {
        guard checksAutomatically, let release = availableUpdate, let currentVersion, !isInstalling else { return }
        switch canInstall(release) ? mode : .notify {
        case .notify:
            announce(.available(release.version, running: currentVersion))
        case .download:
            if downloads.isKept(release) {
                announce(.downloaded(release.version))
            } else if preferences.expiredUpdateVersion != release.version.description {
                await download(release)
            }
        case .install:
            guard release.version != failedAutomaticInstall, isQuietMoment() else { return }
            await install(release, userInitiated: false)
        }
    }

    /// Looks at the permission to notify and follows changes to it. Turned
    /// off, the update choice adapts (`adapt(toNotificationsOff:)`). Reset
    /// in System Settings (Reset Notifications…), which makes macOS treat
    /// AutoHush as never asked, AutoHush asks again at once. Called by each
    /// automatic run and, every second, while Settings is open.
    @discardableResult
    func followNotificationPermission() async -> NotificationPermission {
        let permission = await notifier.permission()
        if permission == .notAsked, let lastPermission, lastPermission != .notAsked {
            logger.notice("Notifications were reset in System Settings: asking again")
            notifier.requestPermission()
        }
        lastPermission = permission
        adapt(toNotificationsOff: permission == .off)
        return permission
    }

    /// With notifications off, "Notify me" and "Download it and notify me"
    /// can't tell the user anything. AutoHush then moves the choice to
    /// "Install it automatically" and turns automatic checks off: it still
    /// installs nothing without the user turning them back on. Returns
    /// whether it changed the settings.
    @discardableResult
    func adapt(toNotificationsOff notificationsOff: Bool) -> Bool {
        guard notificationsOff, mode != .install else { return false }
        logger.notice("Notifications are off: update choice set to install, automatic checks off")
        mode = .install
        checksAutomatically = false
        onSettingsChange()
        return true
    }
}
