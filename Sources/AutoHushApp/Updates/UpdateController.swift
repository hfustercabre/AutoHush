import AppKit
import OSLog
import AutoHushKit

/// Update checks against the latest GitHub release, and installing what they
/// find. A check runs from the menu or Settings, and daily when enabled.
/// Automatic checks stay silent: when allowed, they install the new version
/// at a moment when AutoHush can restart unnoticed; until then, or when not
/// allowed, the menu offers "Update Available". Manual checks report their
/// result, and offer to install.
@MainActor
final class UpdateController {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersion: AppVersion?
    /// A newer release found by the last check.
    private(set) var availableUpdate: AppRelease? {
        didSet { reportOffer() }
    }
    /// An update is being downloaded and installed. The menu stops offering
    /// it meanwhile.
    private(set) var isInstalling = false {
        didSet { reportOffer() }
    }

    private let checker: UpdateChecker
    private let installer: any UpdateInstalling
    private let preferences: Preferences
    /// Whether AutoHush can restart right now without anyone noticing.
    private let isQuietMoment: @MainActor () -> Bool
    /// Quits AutoHush; the installed update then opens.
    private let quit: @MainActor () -> Void
    /// The release the menu offers.
    private let onAvailableUpdate: @MainActor (AppRelease?) -> Void
    /// The last check's or install's outcome in one line, shown in Settings.
    private let onStatus: @MainActor (String) -> Void
    private var timer: Timer?
    /// A check is under way; one asked for meanwhile is answered by it.
    private var isChecking = false
    /// Someone asked for the check under way, so its result is shown.
    private var resultWanted = false
    /// A version that failed to install automatically. It isn't tried
    /// automatically again until AutoHush restarts.
    private var failedAutomaticInstall: AppVersion?
    private let logger = Logger(category: "Updates")

    init(
        checker: UpdateChecker,
        installer: any UpdateInstalling,
        preferences: Preferences,
        currentVersion: AppVersion?,
        isQuietMoment: @escaping @MainActor () -> Bool,
        quit: @escaping @MainActor () -> Void,
        onAvailableUpdate: @escaping @MainActor (AppRelease?) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        self.checker = checker
        self.installer = installer
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.isQuietMoment = isQuietMoment
        self.quit = quit
        self.onAvailableUpdate = onAvailableUpdate
        self.onStatus = onStatus
    }

    var checksAutomatically: Bool {
        get { preferences.checksForUpdatesAutomatically }
        set { preferences.checksForUpdatesAutomatically = newValue }
    }

    var installsAutomatically: Bool {
        get { preferences.installsUpdatesAutomatically }
        set { preferences.installsUpdatesAutomatically = newValue }
    }

    /// Why this copy of AutoHush can't install updates, or nil when it can.
    var installUnavailability: UpdateInstallUnavailability? { installer.unavailability }

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

    func isCheckDue(now: Date = Date()) -> Bool {
        guard checksAutomatically else { return false }
        guard let last = preferences.lastUpdateCheck else { return true }
        return now.timeIntervalSince(last) >= Self.automaticCheckInterval
    }

    /// Checks when a check is due, then installs what it found (or what an
    /// earlier check found) when allowed and AutoHush can restart unnoticed.
    /// An update waiting for such a moment is tried again at the next run.
    func runAutomaticTasks() async {
        if isCheckDue() { await check(userInitiated: false) }
        guard checksAutomatically, installsAutomatically,
              let release = availableUpdate, canInstall(release),
              release.version != failedAutomaticInstall,
              isQuietMoment()
        else { return }
        await install(release, userInitiated: false)
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
                onStatus(availableStatus(release))
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

    /// Downloads, checks and installs `release`, then quits so that the new
    /// version opens. An automatic install gives up quietly when AutoHush got
    /// busy while downloading; a failed one asked for by the user is reported.
    func install(_ release: AppRelease, userInitiated: Bool) async {
        guard !isInstalling else { return }
        isInstalling = true
        onStatus(String(localized: "Installing version \(release.version.description)…",
                        comment: "Update status in Settings; %@ is a version number"))
        do {
            let update = try await installer.prepare(release)
            guard userInitiated || isQuietMoment() else {
                installer.discard(update)
                isInstalling = false
                onStatus(availableStatus(release))
                return
            }
            try installer.install(update)
            logger.info("Installed \(release.version.description, privacy: .public); relaunching")
            quit()
        } catch {
            isInstalling = false
            logger.error("Installing \(release.version.description, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn't install version \(release.version.description).",
                            comment: "Update status in Settings; %@ is a version number"))
            if userInitiated {
                presentInstallError(error, release: release)
            } else {
                failedAutomaticInstall = release.version
            }
        }
    }

    /// The "Update Available…" menu item: shows the release found.
    func presentAvailableUpdate() {
        guard let release = availableUpdate else { return }
        present(.available(release))
    }

    private func canInstall(_ release: AppRelease) -> Bool {
        installer.unavailability == nil && release.diskImage != nil
    }

    private func reportOffer() {
        onAvailableUpdate(isInstalling ? nil : availableUpdate)
    }

    private func availableStatus(_ release: AppRelease) -> String {
        String(localized: "Version \(release.version.description) is available.",
               comment: "Update status in Settings; %@ is a version number")
    }

    private func present(_ result: UpdateCheckResult) {
        guard let current = currentVersion?.description else { return } // checks need it, so never missing here
        switch result {
        case .available(let release):
            presentAvailable(release, current: current)
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

    /// Offers to install `release`, or, when AutoHush can't, says how to.
    private func presentAvailable(_ release: AppRelease, current: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "AutoHush \(release.version.description) Is Available",
                                   comment: "Alert title; %@ is the new version number")
        let openPage = String(localized: "Open Release Page", comment: "Update alert button")
        let later = String(localized: "Later", comment: "Update alert button: close it without updating")
        let installable = canInstall(release)
        if installable {
            alert.informativeText = String(localized: "You have version \(current). Installing it restarts AutoHush.",
                                           comment: "Update alert; %@ is the installed version")
            alert.addButton(withTitle: String(localized: "Install and Relaunch", comment: "Update alert button"))
            alert.addButton(withTitle: later)
            alert.addButton(withTitle: openPage)
        } else {
            alert.informativeText = UpdateChecker.isHomebrewInstall
                ? String(localized: "You have version \(current). Update with Homebrew:",
                         comment: "Update alert; %@ is the installed version. The Homebrew command follows.")
                    + "\n\nbrew upgrade --cask autohush"
                : String(localized: "You have version \(current). Download it from GitHub and replace AutoHush in your Applications folder.",
                         comment: "Update alert; %@ is the installed version")
            alert.addButton(withTitle: openPage)
            alert.addButton(withTitle: later)
        }
        NSApp.activate()
        switch (alert.runModal(), installable) {
        case (.alertFirstButtonReturn, true):
            Task { await install(release, userInitiated: true) }
        case (.alertFirstButtonReturn, false), (.alertThirdButtonReturn, true):
            NSWorkspace.shared.open(release.pageURL)
        default:
            break
        }
    }

    /// Says why `release` couldn't be installed, and offers its page to
    /// install it by hand.
    private func presentInstallError(_ error: any Error, release: AppRelease) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Couldn't Install the Update", comment: "Alert title")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "Open Release Page", comment: "Update alert button"))
        alert.addButton(withTitle: String(localized: "Later", comment: "Update alert button: close it without updating"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.pageURL)
        }
    }
}
