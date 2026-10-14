import AppKit
import OSLog
import AutoHushKit

// UpdateController: checking for an update.
extension UpdateController {
    func checkFromUser() {
        Task { await check(userInitiated: true) }
    }

    func checkNow() async {
        await check(userInitiated: true)
    }

    /// Asks GitHub for the latest release. A check asked for while one is
    /// under way (a double click, the automatic one, the menu's while
    /// Settings' runs) doesn't start another: it waits for the one under
    /// way, which shows its result if anyone asked.
    func check(userInitiated: Bool) async {
        resultWanted = resultWanted || userInitiated
        if let checking { return await checking.value }
        let task = Task { await runCheck() }
        checking = task
        await task.value
        checking = nil
        resultWanted = false
    }

    private func runCheck() async {
        guard let currentVersion else {
            let unknown = String(localized: "AutoHush’s version is unknown.",
                                 comment: "Update status in Settings, and the alert after a check asked for from the menu or Settings")
            onStatus(unknown)
            if resultWanted { await presentFailure(unknown) }
            return
        }
        onStatus(UpdateOffer.checkingTitle)
        do {
            let result = try await checker.check(currentVersion: currentVersion)
            preferences.lastUpdateCheck = now()
            switch result {
            case .available(let release):
                latestVersion = release.version
                availableUpdate = release
            case .upToDate(let latest):
                latestVersion = latest
                availableUpdate = nil
            case .noReleases:
                latestVersion = currentVersion
                availableUpdate = nil
            }
            if availableUpdate == nil { withdrawOffer() }
            tidy()
            switch result {
            case .available(let release):
                onStatus(availableStatus(release))
            case .upToDate:
                onStatus(String(localized: "AutoHush \(currentVersion.description) is up to date.",
                                comment: "Update status in Settings; %@ is a version number"))
            case .noReleases:
                onStatus(String(localized: "No releases have been published yet.", comment: "Update status in Settings"))
            }
            if resultWanted {
                await beforePresenting()
                showAlert { self.present(result) }
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn’t check for updates.", comment: "Update status in Settings"))
            if resultWanted { await presentFailure(error.localizedDescription) }
        }
    }

    /// Says why a check asked for couldn't tell, in an alert.
    private func presentFailure(_ reason: String) async {
        await beforePresenting()
        let title = String(localized: "Couldn’t Check for Updates", comment: "Alert title")
        showAlert { InfoAlert.show(title, reason) }
    }
}
