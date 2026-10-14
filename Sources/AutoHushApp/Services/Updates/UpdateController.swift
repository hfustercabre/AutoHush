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
    var availableUpdate: AppRelease? {
        didSet { reportOffer() }
    }
    /// An update is being downloaded and installed.
    var isInstalling = false {
        didSet { reportOffer() }
    }

    let checker: UpdateChecker
    let installer: any UpdateInstalling
    let downloads: UpdateDownloads
    let notifier: any UpdateNotifying
    let preferences: Preferences
    let now: @MainActor () -> Date
    /// Whether AutoHush can restart right now without anyone noticing.
    let isQuietMoment: @MainActor () -> Bool
    /// Quits AutoHush; the installed update then opens.
    let quit: @MainActor () -> Void
    let openURL: @MainActor (URL) -> Void
    /// The update the menu offers.
    let onOffer: @MainActor (UpdateOffer?) -> Void
    /// The last check's, download's or install's outcome in one line, shown in Settings.
    let onStatus: @MainActor (String) -> Void
    /// The update settings changed: the user's choice in Settings, or AutoHush
    /// by itself (`adapt(toNotificationsOff:)`).
    let onSettingsChange: @MainActor () -> Void
    var timer: Timer?
    /// The check under way: one asked for meanwhile is answered by it.
    var checking: Task<Void, Never>?
    /// Someone asked for the check under way, so its result is shown.
    var resultWanted = false
    /// An update is being downloaded to keep.
    var isDownloading = false
    /// The latest version GitHub reported this session; a kept download of
    /// any other version is deleted.
    var latestVersion: AppVersion?
    /// A version that failed to install automatically. It isn't tried
    /// automatically again until AutoHush restarts.
    var failedAutomaticInstall: AppVersion?
    /// The notification permission last seen, to notice a reset.
    var lastPermission: NotificationPermission?
    /// Runs before a check's result shows in an alert: the menu, open while
    /// it checks, closes first.
    var beforePresenting: @MainActor () async -> Void = {}
    /// Shows an alert from the run loop, once the work that asked for it is
    /// done. Run from inside a main-actor task (a check, an install, a
    /// notification's click), an alert's modal loop would hold up every
    /// other main-actor job until it closes: the menu, Settings, the
    /// player's state reports. Tests replace it.
    var showAlert: @MainActor (@escaping @MainActor () -> Void) -> Void = { show in
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated(show) }
    }
    let logger = Logger(category: "Updates")

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
        onStatus: @escaping @MainActor (String) -> Void,
        onSettingsChange: @escaping @MainActor () -> Void = {}
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
        self.onSettingsChange = onSettingsChange
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
}

/// What Settings and the menu ask of the updates.
extension UpdateController: UpdateCommands {}
