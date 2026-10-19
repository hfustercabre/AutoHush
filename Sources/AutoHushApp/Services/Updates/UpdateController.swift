import AppKit
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
///
/// Settings shows what it keeps (its settings, the last status, the last
/// check, whether notifications are off) by reading it: it's observable,
/// so nothing relays them (X17, the full check, 2026-10-19).
@MainActor
@Observable
final class UpdateController {
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersion: AppVersion?
    /// The last check's, download's or install's outcome in one line, e.g.
    /// "Checking…"; `nil` before any.
    private(set) var status: String?
    /// A newer release found by the last check.
    @ObservationIgnored var availableUpdate: AppRelease? {
        didSet { reportOffer() }
    }
    /// An update is being downloaded and installed.
    @ObservationIgnored var isInstalling = false {
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
    /// Hears each status as it's shown, in turn (tests follow them).
    let onStatus: @MainActor (String) -> Void
    @ObservationIgnored var timer: Timer?
    /// The check under way: one asked for meanwhile is answered by it.
    @ObservationIgnored var checking: Task<Void, Never>?
    /// Someone asked for the check under way, so its result is shown.
    @ObservationIgnored var resultWanted = false
    /// An update is being downloaded to keep.
    @ObservationIgnored var isDownloading = false
    /// The latest version GitHub reported this session; a kept download of
    /// any other version is deleted.
    @ObservationIgnored var latestVersion: AppVersion?
    /// A version that failed to install automatically. It isn't tried
    /// automatically again until AutoHush restarts.
    @ObservationIgnored var failedAutomaticInstall: AppVersion?
    /// The notification permission last seen, to notice a reset; Settings
    /// says when it's off.
    var lastPermission: NotificationPermission?
    /// Runs before a check's result shows in an alert: the menu, open while
    /// it checks, closes first.
    @ObservationIgnored var beforePresenting: @MainActor () async -> Void = {}
    /// Shows an alert from the run loop, once the work that asked for it is
    /// done. Run from inside a main-actor task (a check, an install, a
    /// notification's click), an alert's modal loop would hold up every
    /// other main-actor job until it closes: the menu, Settings, the
    /// player's state reports. Tests replace it.
    @ObservationIgnored var showAlert: @MainActor (@escaping @MainActor () -> Void) -> Void = { show in
        RunLoop.main.perform(inModes: [.common]) { MainActor.assumeIsolated(show) }
    }
    /// Runs an alert and returns the button pressed. Tests replace it.
    @ObservationIgnored var runAlert: @MainActor (NSAlert) -> NSApplication.ModalResponse = InfoAlert.runInFront
    let logger = AutoHushLogger(category: "Updates")

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
        onStatus: @escaping @MainActor (String) -> Void = { _ in }
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

    // The settings and the last check are kept in the preferences, and
    // followed as they change there.

    var checksAutomatically: Bool {
        get {
            access(keyPath: \.checksAutomatically)
            return preferences.checksForUpdatesAutomatically
        }
        set {
            withMutation(keyPath: \.checksAutomatically) { preferences.checksForUpdatesAutomatically = newValue }
            tidy()
        }
    }

    /// What happens when an automatic check finds a newer version.
    var mode: AutomaticUpdates {
        get {
            access(keyPath: \.mode)
            return preferences.automaticUpdates
        }
        set {
            withMutation(keyPath: \.mode) { preferences.automaticUpdates = newValue }
            tidy()
        }
    }

    /// When updates were last checked for, by hand or automatically.
    var lastCheck: Date? {
        get {
            access(keyPath: \.lastCheck)
            return preferences.lastUpdateCheck
        }
        set {
            withMutation(keyPath: \.lastCheck) { preferences.lastUpdateCheck = newValue }
        }
    }

    /// The user turned AutoHush's notifications off in System Settings, as
    /// last seen.
    var notificationsOff: Bool { lastPermission == .off }

    /// Shows `status` in Settings.
    func showStatus(_ status: String) {
        self.status = status
        onStatus(status)
    }

    /// Why this copy of AutoHush can't install updates, or nil when it can.
    var installUnavailability: UpdateInstallUnavailability? { installer.unavailability }
}

/// What Settings and the menu ask of the updates.
extension UpdateController: UpdateCommands {}
