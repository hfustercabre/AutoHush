import AppKit
import OSLog
import AutoHushKit

/// Update checks against the latest GitHub release: a manual check from the
/// menu or Settings, and an automatic daily check when enabled. Automatic
/// checks stay silent and only offer "Update Available" in the menu; manual
/// ones report the result.
@MainActor
final class UpdateController {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersion: AppVersion?
    /// A newer release found by the last check, offered in the menu.
    private(set) var availableUpdate: AppRelease? {
        didSet { onAvailableUpdate(availableUpdate) }
    }

    private let checker: UpdateChecker
    private let preferences: Preferences
    private let onAvailableUpdate: @MainActor (AppRelease?) -> Void
    /// The last check's outcome in one line, shown in Settings.
    private let onStatus: @MainActor (String) -> Void
    private var timer: Timer?
    /// A check is under way; one asked for meanwhile is answered by it.
    private var isChecking = false
    /// Someone asked for the check under way, so its result is shown.
    private var resultWanted = false
    private let logger = Logger(category: "Updates")

    init(
        checker: UpdateChecker,
        preferences: Preferences,
        currentVersion: AppVersion?,
        onAvailableUpdate: @escaping @MainActor (AppRelease?) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        self.checker = checker
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.onAvailableUpdate = onAvailableUpdate
        self.onStatus = onStatus
    }

    var checksAutomatically: Bool {
        get { preferences.checksForUpdatesAutomatically }
        set { preferences.checksForUpdatesAutomatically = newValue }
    }

    /// Checks shortly after launch, then hourly, whenever a check is due.
    func scheduleAutomaticChecks() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer.fireDate = Date().addingTimeInterval(30) // let the network come up after login
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func isCheckDue(now: Date = Date()) -> Bool {
        guard checksAutomatically else { return false }
        guard let last = preferences.lastUpdateCheck else { return true }
        return now.timeIntervalSince(last) >= Self.automaticCheckInterval
    }

    func checkIfDue() {
        guard isCheckDue() else { return }
        Task { await check(userInitiated: false) }
    }

    func checkFromUser() {
        Task { await check(userInitiated: true) }
    }

    /// Asks GitHub for the latest release. A check asked for while one is
    /// under way (a double click, the automatic one) doesn't start another:
    /// the one under way answers, and shows its result if anyone asked.
    func check(userInitiated: Bool, now: Date = Date()) async {
        resultWanted = resultWanted || userInitiated
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            resultWanted = false
        }
        guard let currentVersion else {
            onStatus(String(localized: "The app's version is unknown.", comment: "Update status in Settings"))
            return
        }
        onStatus(String(localized: "Checking…", comment: "Update status in Settings: a check is running"))
        do {
            let result = try await checker.check(currentVersion: currentVersion)
            preferences.lastUpdateCheck = now
            switch result {
            case .available(let release):
                availableUpdate = release
                onStatus(String(localized: "Version \(release.version.description) is available.",
                                comment: "Update status in Settings; %@ is a version number"))
            case .upToDate:
                availableUpdate = nil
                onStatus(String(localized: "AutoHush \(currentVersion.description) is up to date.",
                                comment: "Update status in Settings; %@ is a version number"))
            case .noReleases:
                availableUpdate = nil
                onStatus(String(localized: "No releases have been published yet.", comment: "Update status in Settings"))
            }
            if resultWanted { present(result) }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn't check for updates.", comment: "Update status in Settings"))
            if resultWanted {
                let title = String(localized: "Couldn't Check for Updates", comment: "Alert title")
                InfoAlert.show(title, error.localizedDescription)
            }
        }
    }

    /// The "Update Available…" menu item: shows the release found.
    func presentAvailableUpdate() {
        guard let release = availableUpdate else { return }
        present(.available(release))
    }

    private func present(_ result: UpdateCheckResult) {
        guard let current = currentVersion?.description else { return } // checks need it, so never missing here
        switch result {
        case .available(let release):
            let alert = NSAlert()
            alert.messageText = String(localized: "AutoHush \(release.version.description) Is Available",
                                       comment: "Alert title; %@ is the new version number")
            alert.informativeText = UpdateChecker.isHomebrewInstall
                ? String(localized: "You have version \(current). Update with Homebrew:",
                         comment: "Update alert; %@ is the installed version. The Homebrew command follows.")
                    + "\n\nbrew upgrade --cask autohush"
                : String(localized: "You have version \(current). Download it from GitHub and replace AutoHush in your Applications folder.",
                         comment: "Update alert; %@ is the installed version")
            alert.addButton(withTitle: String(localized: "Open Release Page", comment: "Update alert button"))
            alert.addButton(withTitle: String(localized: "Later", comment: "Update alert button: close it without updating"))
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .upToDate:
            InfoAlert.show(
                String(localized: "AutoHush Is Up to Date", comment: "Alert title"),
                String(localized: "You have the latest version, \(current).",
                       comment: "Alert text; %@ is the installed version")
            )
        case .noReleases:
            InfoAlert.show(
                String(localized: "No Releases Yet", comment: "Alert title"),
                String(localized: "No AutoHush release has been published on GitHub yet.", comment: "Alert text")
            )
        }
    }
}
