import AppKit
import OSLog

// Update checks against the latest GitHub release: a manual check from the
// menu or Settings, and an automatic daily check when enabled.
extension AppDelegate {
    static let automaticUpdateCheckInterval: TimeInterval = 24 * 60 * 60

    func setChecksForUpdatesAutomatically(_ enabled: Bool) {
        preferences.checksForUpdatesAutomatically = enabled
        settingsModel.checksForUpdatesAutomatically = enabled
    }

    /// Checks shortly after launch, then hourly, whenever a check is due.
    func scheduleAutomaticUpdateChecks() {
        updateCheckTimer?.invalidate()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdatesIfDue() }
        }
        timer.fireDate = Date().addingTimeInterval(30) // let the network come up after login
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer
    }

    func isUpdateCheckDue(now: Date = Date()) -> Bool {
        guard preferences.checksForUpdatesAutomatically else { return false }
        guard let last = preferences.lastUpdateCheck else { return true }
        return now.timeIntervalSince(last) >= Self.automaticUpdateCheckInterval
    }

    func checkForUpdatesIfDue() {
        guard isUpdateCheckDue() else { return }
        Task { await checkForUpdates(userInitiated: false) }
    }

    func checkForUpdatesFromUser() {
        Task { await checkForUpdates(userInitiated: true) }
    }

    /// Asks GitHub for the latest release. Automatic checks stay silent and
    /// only add "Update Available" to the menu; manual ones report the result.
    func checkForUpdates(userInitiated: Bool, now: Date = Date()) async {
        guard let currentVersion else {
            settingsModel.updateStatus = "The app's version is unknown."
            return
        }
        settingsModel.updateStatus = "Checking…"
        do {
            let result = try await updateChecker.check(currentVersion: currentVersion)
            preferences.lastUpdateCheck = now
            switch result {
            case .available(let release):
                setAvailableUpdate(release)
                settingsModel.updateStatus = "Version \(release.version) is available."
            case .upToDate:
                setAvailableUpdate(nil)
                settingsModel.updateStatus = "AutoHush \(currentVersion) is up to date."
            case .noReleases:
                setAvailableUpdate(nil)
                settingsModel.updateStatus = "No releases have been published yet."
            }
            if userInitiated { presentUpdateResult(result) }
        } catch {
            Logger(category: "Updates").error("Update check failed: \(error.localizedDescription, privacy: .public)")
            settingsModel.updateStatus = "Couldn't check for updates."
            if userInitiated {
                showAlert("Couldn't Check for Updates", error.localizedDescription)
            }
        }
    }

    func presentAvailableUpdate() {
        guard let release = status.availableUpdate else { return }
        presentUpdateResult(.available(release))
    }

    private func presentUpdateResult(_ result: UpdateCheckResult) {
        switch result {
        case .available(let release):
            let howTo = UpdateChecker.isHomebrewInstall
                ? "Update with Homebrew:\n\nbrew upgrade --cask autohush"
                : "Download it from GitHub and replace AutoHush in your Applications folder."
            let alert = NSAlert()
            alert.messageText = "AutoHush \(release.version) Is Available"
            alert.informativeText = "You have version \(currentVersion?.description ?? "unknown"). \(howTo)"
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "Later")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .upToDate:
            showAlert("AutoHush Is Up to Date", "You have the latest version, \(currentVersion?.description ?? "").")
        case .noReleases:
            showAlert("No Releases Yet", "No AutoHush release has been published on GitHub yet.")
        }
    }
}
