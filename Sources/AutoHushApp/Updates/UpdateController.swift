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

    /// Asks GitHub for the latest release.
    func check(userInitiated: Bool, now: Date = Date()) async {
        guard let currentVersion else {
            onStatus("The app's version is unknown.")
            return
        }
        onStatus("Checking…")
        do {
            let result = try await checker.check(currentVersion: currentVersion)
            preferences.lastUpdateCheck = now
            switch result {
            case .available(let release):
                availableUpdate = release
                onStatus("Version \(release.version) is available.")
            case .upToDate:
                availableUpdate = nil
                onStatus("AutoHush \(currentVersion) is up to date.")
            case .noReleases:
                availableUpdate = nil
                onStatus("No releases have been published yet.")
            }
            if userInitiated { present(result) }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            onStatus("Couldn't check for updates.")
            if userInitiated {
                InfoAlert.show("Couldn't Check for Updates", error.localizedDescription)
            }
        }
    }

    /// The "Update Available…" menu item: shows the release found.
    func presentAvailableUpdate() {
        guard let release = availableUpdate else { return }
        present(.available(release))
    }

    private func present(_ result: UpdateCheckResult) {
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
            InfoAlert.show("AutoHush Is Up to Date", "You have the latest version, \(currentVersion?.description ?? "").")
        case .noReleases:
            InfoAlert.show("No Releases Yet", "No AutoHush release has been published on GitHub yet.")
        }
    }
}
