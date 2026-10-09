import Foundation
import Observation
import AutoHushKit

/// What the Settings window shows and edits. `AppDelegate` keeps it in sync
/// with the app's state and performs the actions; launch at login is handled
/// here directly.
@MainActor
@Observable
final class SettingsModel {
    /// What changing a setting does; `AppDelegate` provides them.
    struct Actions {
        var chooseMusicPlayer: @MainActor (String) -> Void
        var setAutoPause: @MainActor (Bool) -> Void
        var setIgnored: @MainActor (AudioSource, Bool) -> Void
        var forgetApp: @MainActor (AudioSource) -> Void
        var forgetAllApps: @MainActor () -> Void
        var setAppListOrder: @MainActor (AppListOrder) -> Void = { _ in }
        var setTimings: @MainActor (TimingSettings) -> Void
        var setDetectionMethod: @MainActor (DetectionMethod) -> Void
        var setChecksForUpdates: @MainActor (Bool) -> Void
        var setAutomaticUpdates: @MainActor (AutomaticUpdates) -> Void
        var checkForUpdates: @MainActor () -> Void
        var openNotificationSettings: @MainActor () -> Void
        /// Brings `diagnostics` up to date.
        var refreshDiagnostics: @MainActor () -> Void = {}
        /// Opens the "Add a Web App" window.
        var addWebApp: @MainActor () -> Void = {}
        /// Forgets the chosen player's learned controls and learns them again.
        var learnControlsAgain: @MainActor () -> Void = {}
        /// The user says, while AutoHush learns the player, that it plays
        /// (It's Playing) or that it's paused (It's Paused).
        var learningStep: @MainActor (StepButton) -> Void = { _ in }
        /// Asks for a missing permission: macOS's prompt, System Settings,
        /// opening the player, or reopening AutoHush (`PermissionCenter`).
        var requestPermission: @MainActor (Permission) -> Void = { _ in }
        /// The welcome window is done: the player chosen, what it needs allowed.
        var finishWelcome: @MainActor () -> Void = {}
    }

    /// One app in Settings → Apps, and whether it is ignored.
    struct AppRow: Identifiable, Equatable {
        let source: AudioSource
        let isIgnored: Bool
        /// When it played, as a place in line: 0 played most recently. `nil`
        /// for an app ignored before it ever played.
        var playedRank: Int?
        var id: String { source.id }
    }

    // General
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginError: String?
    /// macOS waits for the user to allow AutoHush in Login Items.
    private(set) var launchAtLoginNeedsApproval = false
    /// The music players to choose from (also in the welcome window).
    var playerOptions: [PlayerOption] = []
    /// The bundle ID of the chosen player; `nil` while none is chosen.
    var chosenPlayerID: String?
    /// Whether AutoHush can fade the chosen player; the fade settings are
    /// dimmed when it can't.
    var playerCanFade = true

    /// How far AutoHush has come learning to control the chosen player;
    /// `nil` for a player it controls without learning.
    var learning: LearningStatus?
    /// Once the user said the chosen player plays: when learning starts
    /// over without the pause.
    var learningPauseDeadline: Date?
    /// Why the user's last learning click didn't move it on.
    var learningNote: LearningNote?
    /// Once the user said it plays: AutoHush pauses it itself, to learn
    /// which button changes, or, when it couldn't, the user does.
    var learningPauseMode = LearningPauseMode.automatic
    /// A permission the chosen player needs is missing: its learning steps
    /// wait until it's allowed (the menu asks for it).
    var playerNeedsPermission = false
    /// What AutoHush needs for the chosen player, as it stands; followed
    /// about once a second while a window that waits for it shows.
    var permissions = PermissionsState()
    /// The welcome window shows what the chosen player needs, after its list.
    var welcomeAsksPermissions = false

    /// The chosen player as it's offered.
    var chosenPlayer: PlayerOption? {
        playerOptions.first { $0.bundleID == chosenPlayerID }
    }

    /// The chosen player's name, e.g. "Spotify".
    var chosenPlayerName: String? { chosenPlayer?.name }

    /// Whether the user has still to play the chosen player (`false`) or to
    /// pause it (`true`) so AutoHush learns it; `nil` once there's nothing
    /// to learn, or while the chosen player isn't offered (deleted).
    var learningHasPlayed: Bool? {
        guard chosenPlayer != nil, !playerNeedsPermission, case .learning(let hasPlayed) = learning else { return nil }
        return hasPlayed
    }
    /// The chosen player's controls are learned, so they can be learned
    /// again (they may have been learned wrong).
    var canLearnControlsAgain: Bool { chosenPlayer != nil && learning == .learned }
    var isAutoPauseOn = true
    /// E.g. "Turned off until 15:30.", shown under the auto-pause switch.
    var autoPauseNote: String?
    var detectionMethod = DetectionMethod.audioLevels
    var checksForUpdatesAutomatically = true
    /// What automatic checks lead to: notify, download or install.
    var automaticUpdates = AutomaticUpdates.install
    /// Why AutoHush can't install updates itself, shown under the choice;
    /// nil when it can. Then only "Notify me" is possible.
    var updateInstallNote: String?
    /// The user turned AutoHush's notifications off in System Settings. Then
    /// the update choices that rely on them are unavailable.
    var notificationsOff = false
    /// The "notifications are off" note is shown lit: it blinks after a click
    /// on an unavailable choice (`flashNotificationsNote`).
    private(set) var notificationsNoteIsLit = false
    /// How long the note blinks, and how fast.
    @ObservationIgnored var noteFlashDuration: Duration = .seconds(5)
    @ObservationIgnored var noteFlashInterval: Duration = .milliseconds(500)
    @ObservationIgnored private var noteFlashEnd: ContinuousClock.Instant?
    @ObservationIgnored private var noteFlash: Task<Void, Never>?
    /// What the last check from Settings found, e.g. "Checking…".
    var updateStatus: String?
    /// This copy's version, e.g. "0.3.11"; `nil` when unknown.
    var currentVersion: String?
    /// The version with its build number, e.g. "0.6.1 (19)", for About and
    /// Diagnostics.
    var fullVersion: String? {
        guard let currentVersion else { return nil }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(currentVersion) (\($0))" } ?? currentVersion
    }
    /// When updates were last checked for, by hand or automatically.
    var lastUpdateCheck: Date?

    // Apps
    /// The apps, in `appListOrder`.
    private(set) var apps: [AppRow] = []
    /// How the apps are ordered; the most recent first unless the user
    /// chose otherwise.
    private(set) var appListOrder = AppListOrder.standard
    /// The search in Settings → Apps: `nil` while it's closed. It's closed
    /// again each time Settings opens.
    var appSearch: String?
    /// The apps whose names match the search, ignoring case and accents, in
    /// `appListOrder`; all of them while there's nothing to search for.
    var shownApps: [AppRow] {
        let query = appSearch?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.source.name.localizedStandardContains(query) }
    }
    /// The tallest Settings → Apps may grow while its list is long: the
    /// height of Advanced, so switching between them keeps the window still.
    var appsMaximumHeight: CGFloat = 585
    /// The app clicked in Settings → Apps, which Remove takes off the list.
    private(set) var selectedAppID: String?
    /// The selected app, while the list shows it (the search may hide it).
    var selectedApp: AppRow? { shownApps.first { $0.id == selectedAppID } }
    /// A turned-off app the user asked to remove, while that's confirmed.
    private(set) var appAwaitingRemoval: AppRow?
    /// Its name, kept while the confirmation closes (its title shows it).
    private(set) var removalName = ""

    // Diagnostics
    /// What AutoHush sees, kept up to date while the Diagnostics tab shows.
    var diagnostics: DiagnosticsSnapshot?
    /// The parts of Diagnostics the user folded away; all open again each
    /// time Settings opens.
    var foldedDiagnostics: Set<DiagnosticsSnapshot.Part> = []

    // Advanced
    var timings = TimingSettings.defaults

    /// The row with Check Now: what the last check found ("AutoHush 0.3.11
    /// is up to date.", "Checking…"), or this version before any check.
    var updateTitle: String {
        updateStatus ?? currentVersion.map {
            String(localized: "AutoHush \($0)", comment: "Settings, beside Check Now before any check; %@ is the version")
        } ?? "AutoHush"
    }

    /// Under it: "Last checked 2 hours ago"; `nil` before the first check.
    func lastCheckedNote(now: Date = Date()) -> String? {
        guard let lastUpdateCheck else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let when = formatter.localizedString(for: lastUpdateCheck, relativeTo: now)
        return String(localized: "Last checked \(when)", comment: "Settings, beside Check Now; %@ is e.g. “2 hours ago”")
    }

    /// AntiDot mode: no visual signs of AutoHush working — it never
    /// captures audio, so macOS never shows the purple recording indicator.
    var isAntiDotMode: Bool { detectionMethod != .audioLevels }

    @ObservationIgnored private let launchAtLoginController: any LaunchAtLoginControlling
    @ObservationIgnored private let actions: Actions

    init(launchAtLoginController: any LaunchAtLoginControlling, actions: Actions) {
        self.launchAtLoginController = launchAtLoginController
        self.actions = actions
        refreshLaunchAtLogin()
    }

    // MARK: - Launch at login

    func refreshLaunchAtLogin() {
        let enabled = launchAtLoginController.isEnabled, needsApproval = launchAtLoginController.needsApproval
        if launchAtLoginEnabled != enabled { launchAtLoginEnabled = enabled }
        if launchAtLoginNeedsApproval != needsApproval { launchAtLoginNeedsApproval = needsApproval }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch launchAtLoginController.setEnabled(enabled) {
        case .success:
            launchAtLoginError = nil
        case .failure(let error):
            launchAtLoginError = String(localized: "Couldn't change the login item: \(error.localizedDescription)",
                                        comment: "Settings, under Launch at login; %@ is the error macOS reported")
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    // MARK: - Forwarded actions

    func chooseMusicPlayer(_ bundleID: String) { actions.chooseMusicPlayer(bundleID) }
    func addWebApp() { actions.addWebApp() }
    func learnControlsAgain() { actions.learnControlsAgain() }
    func learningStep(_ button: StepButton) { actions.learningStep(button) }
    func setAutoPause(_ on: Bool) { actions.setAutoPause(on) }
    func setPausesMusic(_ pauses: Bool, for source: AudioSource) { actions.setIgnored(source, !pauses) }
    func forget(_ source: AudioSource) { actions.forgetApp(source) }

    /// A click on an app in Settings → Apps: selects it, or unselects it.
    func toggleSelection(of id: String) {
        selectedAppID = selectedAppID == id ? nil : id
    }

    /// Settings closed: a selection doesn't outlive it.
    func clearSelection() { selectedAppID = nil }

    /// Remove (or Remove from List): takes the app off the list. One that's
    /// turned off would pause the music again, so that's asked first
    /// (`appAwaitingRemoval`).
    func remove(_ row: AppRow) {
        if row.isIgnored {
            removalName = row.source.name
            appAwaitingRemoval = row
        } else {
            takeOff(row)
        }
    }

    /// The turned-off app is removed after all.
    func confirmRemoval() {
        guard let row = appAwaitingRemoval else { return }
        appAwaitingRemoval = nil
        takeOff(row)
    }

    /// The confirmation closed without removing it.
    func cancelRemoval() { appAwaitingRemoval = nil }

    private func takeOff(_ row: AppRow) {
        forget(row.source)
        if selectedAppID == row.id { selectedAppID = nil }
    }
    func forgetAllApps() { actions.forgetAllApps() }

    func setAppListOrder(_ order: AppListOrder) {
        guard order != appListOrder else { return }
        appListOrder = order
        apps = Self.ordered(apps, by: order)
        actions.setAppListOrder(order)
    }
    func setChecksForUpdates(_ on: Bool) { actions.setChecksForUpdates(on) }
    func setAutomaticUpdates(_ mode: AutomaticUpdates) { actions.setAutomaticUpdates(mode) }

    /// Whether `mode` can be chosen now: notifying needs notifications.
    func isAvailable(_ mode: AutomaticUpdates) -> Bool {
        mode == .install || !notificationsOff
    }

    /// Makes the "notifications are off" note blink for `noteFlashDuration`;
    /// asked again meanwhile, it blinks that long from then.
    func flashNotificationsNote() {
        let clock = ContinuousClock()
        noteFlashEnd = clock.now + noteFlashDuration
        guard noteFlash == nil else { return }
        notificationsNoteIsLit = true
        let interval = noteFlashInterval
        noteFlash = Task { [weak self] in
            while true {
                try? await Task.sleep(for: interval)
                guard let self, let end = self.noteFlashEnd, clock.now < end else { break }
                self.notificationsNoteIsLit.toggle()
            }
            self?.notificationsNoteIsLit = false
            self?.noteFlash = nil
        }
    }
    func checkForUpdates() { actions.checkForUpdates() }
    func openNotificationSettings() { actions.openNotificationSettings() }
    func requestPermission(_ permission: Permission) { actions.requestPermission(permission) }
    func finishWelcome() { actions.finishWelcome() }

    /// Back to the welcome window's list, to choose another player.
    func showWelcomePlayers() { welcomeAsksPermissions = false }

    /// AntiDot mode doesn't need Audio Recording: the way past it without allowing it.
    func useAntiDotMode() { setDetectionMethod(.playbackSignals) }
    func refreshDiagnostics() { actions.refreshDiagnostics() }

    func setTimings(_ timings: TimingSettings) {
        self.timings = timings.clamped
        actions.setTimings(self.timings)
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        detectionMethod = method
        actions.setDetectionMethod(method)
    }

    /// On: judges apps by what they tell macOS (the indicator-free method
    /// that keeps the most accuracy). Off: measures audio levels.
    func setAntiDotMode(_ on: Bool) {
        guard on != isAntiDotMode else { return }
        setDetectionMethod(on ? .playbackSignals : .audioLevels)
    }

    func restoreDefaultTimings() {
        setTimings(.defaults)
    }

    // MARK: - Updates from the app

    /// Apps that have played audio, the most recent first, plus ignored
    /// apps, shown in `order` (the one already chosen when `nil`).
    func setApps(seen: [AudioSource], ignored: [AudioSource], order: AppListOrder? = nil) {
        if let order { appListOrder = order }
        let ignoredIDs = Set(ignored.map(\.id))
        var rows = seen.enumerated().map {
            AppRow(source: $0.element, isIgnored: ignoredIDs.contains($0.element.id), playedRank: $0.offset)
        }
        for app in ignored where !rows.contains(where: { $0.id == app.id }) {
            rows.append(AppRow(source: app, isIgnored: true))
        }
        apps = Self.ordered(rows, by: appListOrder)
    }

    /// The rows in `order`. Ties, and the apps that never played, go by name;
    /// for a reversed On/Off order, only the groups swap.
    static func ordered(_ rows: [AppRow], by order: AppListOrder) -> [AppRow] {
        let name = { (row: AppRow) in row.source.name.localizedLowercase }
        switch order.criterion {
        case .lastPlayed:
            let rank = { (row: AppRow) in row.playedRank ?? .max }
            let list = rows.sorted { (rank($0), name($0), $0.id) < (rank($1), name($1), $1.id) }
            return order.isReversed ? list.reversed() : list
        case .name:
            let list = rows.sorted { (name($0), $0.id) < (name($1), $1.id) }
            return order.isReversed ? list.reversed() : list
        case .state:
            let group = { (row: AppRow) in row.isIgnored != order.isReversed ? 1 : 0 }
            return rows.sorted { (group($0), name($0), $0.id) < (group($1), name($1), $1.id) }
        }
    }
}
