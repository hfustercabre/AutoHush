import AppKit
import OSLog
import AutoHushKit

// UpdateController: checking for an update.
extension UpdateController {
    func checkFromUser() {
        Task { await check(userInitiated: true) }
    }

    /// Asks GitHub for the latest release. A check asked for while one is
    /// under way (a double click, the automatic one) doesn't start another:
    /// the one under way answers, and shows its result if anyone asked.
    func check(userInitiated: Bool) async {
        resultWanted = resultWanted || userInitiated
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            resultWanted = false
        }
        guard let currentVersion else {
            onStatus(String(localized: "The app’s version is unknown.", comment: "Update status in Settings"))
            return
        }
        onStatus(String(localized: "Checking…", comment: "Update status in Settings: a check is running"))
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
            if resultWanted { present(result) }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn’t check for updates.", comment: "Update status in Settings"))
            if resultWanted {
                let title = String(localized: "Couldn’t Check for Updates", comment: "Alert title")
                InfoAlert.show(title, error.localizedDescription)
            }
        }
    }
}
