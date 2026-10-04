import AppKit
import OSLog
import AutoHushKit

/// Update checks against the latest GitHub release, and what follows them.
/// A check runs from the menu or Settings, and daily when enabled.
///
/// What an automatic check leads to is the user's choice (`mode`):
/// - **notify**: a notification, and the menu offers the update;
/// - **download**: the update is downloaded and kept (`UpdateDownloads`),
///   then a notification; installing it later is quick;
/// - **install**: it's installed at a moment when AutoHush can restart
///   unnoticed, and the new version says so in a notification.
///
/// Until it's installed, the menu offers it ("Install AutoHush 0.3.8…"), and
/// its popup tells which version is running, which one is available or
/// downloaded, and what's new. Manual checks report their result.
@MainActor
final class UpdateController {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersion: AppVersion?
    /// A newer release found by the last check.
    private(set) var availableUpdate: AppRelease? {
        didSet { reportOffer() }
    }
    /// An update is being downloaded and installed.
    private(set) var isInstalling = false {
        didSet { reportOffer() }
    }

    private let checker: UpdateChecker
    private let installer: any UpdateInstalling
    private let downloads: UpdateDownloads
    private let notifier: any UpdateNotifying
    private let preferences: Preferences
    private let now: @MainActor () -> Date
    /// Whether AutoHush can restart right now without anyone noticing.
    private let isQuietMoment: @MainActor () -> Bool
    /// Quits AutoHush; the installed update then opens.
    private let quit: @MainActor () -> Void
    private let openURL: @MainActor (URL) -> Void
    /// The update the menu offers.
    private let onOffer: @MainActor (UpdateOffer?) -> Void
    /// The last check's, download's or install's outcome in one line, shown in Settings.
    private let onStatus: @MainActor (String) -> Void
    private var timer: Timer?
    /// A check is under way; one asked for meanwhile is answered by it.
    private var isChecking = false
    /// Someone asked for the check under way, so its result is shown.
    private var resultWanted = false
    /// An update is being downloaded to keep.
    private var isDownloading = false
    /// The latest version GitHub reported this session; a kept download of
    /// any other version is deleted.
    private var latestVersion: AppVersion?
    /// A version that failed to install automatically. It isn't tried
    /// automatically again until AutoHush restarts.
    private var failedAutomaticInstall: AppVersion?
    private let logger = Logger(category: "Updates")

    init(
        checker: UpdateChecker,
        installer: any UpdateInstalling,
        notifier: any UpdateNotifying,
        preferences: Preferences,
        downloadsFolder: URL = UpdateDownloads.defaultFolder,
        currentVersion: AppVersion?,
        now: @escaping @MainActor () -> Date = { Date() },
        isQuietMoment: @escaping @MainActor () -> Bool,
        quit: @escaping @MainActor () -> Void,
        openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
        onOffer: @escaping @MainActor (UpdateOffer?) -> Void,
        onStatus: @escaping @MainActor (String) -> Void
    ) {
        self.checker = checker
        self.installer = installer
        self.downloads = UpdateDownloads(folder: downloadsFolder, preferences: preferences, installer: installer)
        self.notifier = notifier
        self.preferences = preferences
        self.currentVersion = currentVersion
        self.now = now
        self.isQuietMoment = isQuietMoment
        self.quit = quit
        self.openURL = openURL
        self.onOffer = onOffer
        self.onStatus = onStatus
        notifier.onClick = { [weak self] kind, version in self?.open(kind, version: version) }
    }

    var checksAutomatically: Bool {
        get { preferences.checksForUpdatesAutomatically }
        set {
            preferences.checksForUpdatesAutomatically = newValue
            tidy()
        }
    }

    /// What happens when an automatic check finds a newer version.
    var mode: AutomaticUpdates {
        get { preferences.automaticUpdates }
        set {
            preferences.automaticUpdates = newValue
            tidy()
        }
    }

    /// Why this copy of AutoHush can't install updates, or nil when it can.
    var installUnavailability: UpdateInstallUnavailability? { installer.unavailability }

    // MARK: - Launch and scheduling

    /// At launch: listens for clicks on notifications, says so when AutoHush
    /// was updated since it last ran, and tidies a kept download.
    func noteLaunch() {
        notifier.activate()
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

    // MARK: - Checking

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
            onStatus(String(localized: "The app's version is unknown.", comment: "Update status in Settings"))
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
            onStatus(String(localized: "Couldn't check for updates.", comment: "Update status in Settings"))
            if resultWanted {
                let title = String(localized: "Couldn't Check for Updates", comment: "Alert title")
                InfoAlert.show(title, error.localizedDescription)
            }
        }
    }

    // MARK: - Downloading and installing

    /// Downloads `release` and keeps it, then lets the user know. A failed
    /// download is tried again at the next automatic run.
    private func download(_ release: AppRelease) async {
        guard !isDownloading else { return }
        isDownloading = true
        defer { isDownloading = false }
        let version = release.version.description
        onStatus(String(localized: "Downloading version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        do {
            try await downloads.store(release, at: now(), allowsConstrainedNetwork: false)
            preferences.expiredUpdateVersion = nil
            reportOffer()
            onStatus(availableStatus(release))
            announce(.downloaded(release.version))
        } catch {
            logger.error("Downloading \(version, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn't download version \(version).",
                            comment: "Update status in Settings; %@ is a version number"))
        }
    }

    /// Installs `release`, from a kept download when there's an intact one,
    /// then quits so that the new version opens. An automatic install gives
    /// up quietly when AutoHush got busy meanwhile; a failed one is reported:
    /// in an alert when the user asked for it, otherwise in a notification.
    func install(_ release: AppRelease, userInitiated: Bool) async {
        guard !isInstalling else { return }
        isInstalling = true
        let version = release.version.description
        onStatus(String(localized: "Installing version \(version)…",
                        comment: "Update status in Settings; %@ is a version number"))
        let image = downloads.image(for: release)
        do {
            // Automatic installs, like automatic downloads, wait out Low Data Mode.
            let update = try await installer.prepare(release, image: image, allowsConstrainedNetwork: userInitiated)
            guard userInitiated || isQuietMoment() else {
                installer.discard(update)
                isInstalling = false
                onStatus(availableStatus(release))
                return
            }
            try installer.install(update)
            downloads.remove()
            logger.info("Installed \(version, privacy: .public); relaunching")
            quit()
        } catch {
            // A kept download that didn't install isn't trusted again.
            if image != nil { downloads.remove() }
            isInstalling = false
            logger.error("Installing \(version, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            onStatus(String(localized: "Couldn't install version \(version).",
                            comment: "Update status in Settings; %@ is a version number"))
            if userInitiated {
                presentInstallError(error, release: release)
            } else {
                failedAutomaticInstall = release.version
                announce(.installFailed(release.version))
            }
        }
    }

    // MARK: - Notifications

    /// Sends `notice`, unless it was the last one sent.
    private func announce(_ notice: UpdateNotice) {
        guard preferences.lastUpdateNotice != notice.key else { return }
        preferences.lastUpdateNotice = notice.key
        notifier.announce(notice)
    }

    /// Removes a notification about an update that no longer applies: one
    /// saying it's available, downloaded or failed, never "updated to".
    private func withdrawOffer() {
        guard let notice = preferences.lastUpdateNotice,
              !notice.hasPrefix(UpdateNotice.Kind.installed.rawValue + " ")
        else { return }
        notifier.withdraw()
    }

    /// Where a click on a notification leads: for "updated to", that
    /// release's page; otherwise the update's popup, as things stand now.
    func open(_ kind: UpdateNotice.Kind, version: AppVersion) {
        switch kind {
        case .installed:
            openURL(ProjectInfo.releasePage(for: version))
        case .available, .downloaded, .installFailed:
            presentAvailableUpdate()
        }
    }

    // MARK: - Kept download

    /// Deletes a kept download that's no longer wanted (see
    /// `UpdateDownloads.tidy`). Downloads are kept only while automatic checks
    /// are on and the choice isn't "Notify me".
    private func tidy() {
        guard !isDownloading else { return }
        let keeping = checksAutomatically && mode != .notify && installUnavailability == nil
        let hadDownload = preferences.downloadedUpdate != nil
        downloads.tidy(running: currentVersion, latest: latestVersion, keeping: keeping, now: now())
        if let expired = preferences.expiredUpdateVersion.flatMap(AppVersion.init), let currentVersion,
           expired <= currentVersion {
            preferences.expiredUpdateVersion = nil
        }
        if hadDownload, preferences.downloadedUpdate == nil {
            withdrawOffer()
            reportOffer()
        }
    }

    // MARK: - Presenting

    /// The menu's "Install AutoHush 0.3.8…": shows the update found. Clicked
    /// from a notification that no longer applies, it checks again instead.
    func presentAvailableUpdate() {
        guard let release = availableUpdate else {
            checkFromUser()
            return
        }
        present(.available(release))
    }

    private func canInstall(_ release: AppRelease) -> Bool {
        installer.unavailability == nil && release.diskImage != nil
    }

    private func reportOffer() {
        guard let release = availableUpdate else { return onOffer(nil) }
        let state: UpdateOffer.State = isInstalling ? .installing : downloads.isKept(release) ? .downloaded : .available
        onOffer(UpdateOffer(release: release, state: state))
    }

    private func availableStatus(_ release: AppRelease) -> String {
        let version = release.version.description
        return downloads.isKept(release)
            ? String(localized: "Version \(version) is downloaded and ready to install.",
                     comment: "Update status in Settings; %@ is a version number")
            : String(localized: "Version \(version) is available.",
                     comment: "Update status in Settings; %@ is a version number")
    }

    private func present(_ result: UpdateCheckResult) {
        guard let current = currentVersion else { return } // checks need it, so never missing here
        switch result {
        case .available(let release):
            presentAvailable(release, running: current)
        case .upToDate:
            InfoAlert.show(
                String(localized: "AutoHush Is Up to Date", comment: "Alert title"),
                String(localized: "You have the latest version, \(current.description).",
                       comment: "Alert text; %@ is the installed version")
            )
        case .noReleases:
            InfoAlert.show(
                String(localized: "No Releases Yet", comment: "Alert title"),
                String(localized: "No AutoHush release has been published on GitHub yet.", comment: "Alert text")
            )
        }
    }

    /// Offers to install `release`, with its notes, or, when AutoHush can't,
    /// says how to.
    private func presentAvailable(_ release: AppRelease, running: AppVersion) {
        let prompt = UpdatePrompt(
            release: release, running: running, isDownloaded: downloads.image(for: release) != nil,
            canInstall: canInstall(release), isHomebrewInstall: UpdateChecker.isHomebrewInstall
        )
        let alert = NSAlert()
        alert.messageText = prompt.title
        alert.informativeText = prompt.message
        for button in prompt.buttons { alert.addButton(withTitle: button.title) }
        if let notes = release.notes { alert.accessoryView = Self.notesView(notes) }
        NSApp.activate()
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard prompt.buttons.indices.contains(index) else { return }
        switch prompt.buttons[index].choice {
        case .install: Task { await install(release, userInitiated: true) }
        case .openReleasePage: openURL(release.pageURL)
        case .later: break
        }
    }

    /// The release notes in a small scrolling box, as tall as they need up to
    /// a limit, showing their start.
    static func notesView(_ markdown: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 100))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = false
        // Not selectable either, so the alert doesn't make it the first
        // responder, which would scroll it to the middle.
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textStorage?.setAttributedString(ReleaseNotes.text(from: markdown))
        textView.sizeToFit()

        scrollView.frame.size.height = min(max(textView.frame.height + 4, 48), 180)
        scrollView.documentView = textView
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        return scrollView
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
            openURL(release.pageURL)
        }
    }
}
