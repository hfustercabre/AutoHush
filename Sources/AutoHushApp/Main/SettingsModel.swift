import Foundation
import Observation
import AutoHushKit

/// What the Settings window shows and edits, and the welcome, learning and
/// Add a Web App windows with it. What the app's state holds (the chosen
/// player, the status line, Auto-Pause, learning and its pause, the apps)
/// it reads from `AppState`; the rest `AppDelegate` keeps in sync here. The
/// views' actions go to the modules that own them (`settings`, `updates`,
/// `learningSession`), or to `actions` for what only AppDelegate does. Launch at
/// login is handled here directly.
@MainActor
@Observable
final class SettingsModel {
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
    /// Whether AutoHush can fade the chosen player; the fade settings are
    /// dimmed when it can't.
    var playerCanFade = true

    /// What AutoHush needs for the chosen player, as it stands; followed
    /// about once a second while a window that waits for it shows.
    var permissions = PermissionsState()
    /// The welcome window shows what the chosen player needs, after its list.
    var welcomeAsksPermissions = false

    // From the app's state.
    /// The music players to choose from (also in the welcome window).
    var playerOptions: [PlayerOption] { state.status.playerOptions }
    /// The bundle ID of the chosen player; `nil` while none is chosen.
    var chosenPlayerID: String? { state.status.chosenPlayerID }
    /// The chosen player as it's offered.
    var chosenPlayer: PlayerOption? { state.status.chosenPlayer }
    /// The chosen player's name, e.g. "Spotify".
    var chosenPlayerName: String? { chosenPlayer?.name }
    /// How far AutoHush has come learning to control the chosen player;
    /// `nil` for a player it controls without learning.
    var learning: LearningStatus? { state.status.learning }
    /// Its controls can be learned afresh (see `AppStatus`).
    var canLearnControlsAgain: Bool { state.status.canLearnControlsAgain }
    /// Once the user said the chosen player plays: when learning starts
    /// over without the pause.
    var learningPauseDeadline: Date? { state.status.learningPause.deadline }
    /// Why the user's last learning click didn't move it on.
    var learningNote: LearningNote? { state.status.learningPause.note }
    /// Once the user said it plays: AutoHush pauses it itself, to learn
    /// which button changes, or, when it couldn't, the user does.
    var learningPauseMode: LearningPauseMode { state.status.learningPause.mode }
    /// What the music player is doing, as the menu's card says it, e.g.
    /// "Paused — Safari is playing"; orange (`statusNeedsAttention`) when
    /// something needs the user.
    var statusLine: String { state.status.statusLine }
    var statusNeedsAttention: Bool { state.status.needsAttention }
    var isAutoPauseOn: Bool { state.status.autoPause == .on }
    /// E.g. "Turned off until 15:30.", shown under the auto-pause switch.
    var autoPauseNote: String? { state.status.autoPause.settingsNote }

    var detectionMethod: DetectionMethod
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
    /// The apps that played sound, the most recent first, plus the ignored
    /// ones, in `appListOrder`.
    var apps: [AppRow] {
        Self.ordered(Self.rows(seen: state.status.seenApps, ignored: state.status.ignoredApps), by: appListOrder)
    }
    /// How the apps are ordered; the most recent first unless the user
    /// chose otherwise.
    var appListOrder: AppListOrder
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

    // Detection and Fades
    var timings: TimingSettings

    /// Detection's timings shown (pause after, resume after, and the
    /// silence threshold while AntiDot mode is off) are their defaults, so
    /// its Restore Defaults has nothing to do.
    var detectionTimingsAreDefaults: Bool { timings.withDefaultDetection(threshold: !isAntiDotMode) == timings }
    /// The fades (the switch and both lengths) are their defaults.
    var fadesAreDefaults: Bool { timings.withDefaultFades == timings }

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

    /// What the menu shows too, and learning's pause.
    @ObservationIgnored let state: AppState
    /// The user's settings: Settings changes them there.
    @ObservationIgnored let settings: UserSettings
    /// Update checks, and their settings.
    @ObservationIgnored let updates: any UpdateCommands
    /// Learning the chosen web app's controls: its windows' steps.
    @ObservationIgnored let learningSession: LearningSession
    /// What only AppDelegate does: choosing a player, its windows, the
    /// permissions.
    @ObservationIgnored weak var actions: (any AppActions)?
    @ObservationIgnored private let launchAtLoginController: any LaunchAtLoginControlling

    init(state: AppState = AppState(), settings: UserSettings, updates: any UpdateCommands,
         learningSession: LearningSession = LearningSession(), actions: (any AppActions)?,
         launchAtLoginController: any LaunchAtLoginControlling) {
        self.state = state
        self.settings = settings
        self.updates = updates
        self.learningSession = learningSession
        self.actions = actions
        self.launchAtLoginController = launchAtLoginController
        appListOrder = settings.state.listOrder
        timings = settings.state.timings
        detectionMethod = settings.state.detection
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
            launchAtLoginError = String(localized: "Couldn’t change the login item: \(error.localizedDescription)",
                                        comment: "Settings, under Launch at login; %@ is the error macOS reported")
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    // MARK: - Apps

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
        settings.forget(row.source)
        if selectedAppID == row.id { selectedAppID = nil }
    }

    func setAppListOrder(_ order: AppListOrder) {
        guard order != appListOrder else { return }
        appListOrder = order
        settings.setListOrder(order)
    }

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

    /// Back to the welcome window's list, to choose another player.
    func showWelcomePlayers() { welcomeAsksPermissions = false }

    /// AntiDot mode doesn't need Audio Recording: the way past it without allowing it.
    func useAntiDotMode() { setDetectionMethod(.playbackSignals) }

    func setTimings(_ timings: TimingSettings) {
        self.timings = timings.clamped
        settings.setTimings(self.timings)
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        detectionMethod = method
        settings.setDetectionMethod(method)
    }

    /// On: judges apps by what they tell macOS (the indicator-free method
    /// that keeps the most accuracy). Off: measures audio levels.
    func setAntiDotMode(_ on: Bool) {
        guard on != isAntiDotMode else { return }
        setDetectionMethod(on ? .playbackSignals : .audioLevels)
    }

    /// Settings → Detection's Restore Defaults: the timings it shows only,
    /// not the silence threshold hidden in AntiDot mode, nor the fades on
    /// the other page.
    func restoreDefaultDetectionTimings() {
        setTimings(timings.withDefaultDetection(threshold: !isAntiDotMode))
    }

    /// Settings → Fades' Restore Defaults: the fades only.
    func restoreDefaultFades() {
        setTimings(timings.withDefaultFades)
    }

    // MARK: - The apps' rows

    /// A row for each app that played audio, ranked the most recent first,
    /// then one for each ignored app that never played.
    static func rows(seen: [AudioSource], ignored: [AudioSource]) -> [AppRow] {
        let ignoredIDs = Set(ignored.map(\.id))
        var rows = seen.enumerated().map {
            AppRow(source: $0.element, isIgnored: ignoredIDs.contains($0.element.id), playedRank: $0.offset)
        }
        for app in ignored where !rows.contains(where: { $0.id == app.id }) {
            rows.append(AppRow(source: app, isIgnored: true))
        }
        return rows
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

private extension TimingSettings {
    /// These timings with Detection's back to their defaults, the silence
    /// threshold too when `threshold`.
    func withDefaultDetection(threshold: Bool) -> TimingSettings {
        var timings = self
        timings.startConfirmation = TimingSettings.defaults.startConfirmation
        timings.stopGrace = TimingSettings.defaults.stopGrace
        if threshold { timings.silenceThresholdDB = TimingSettings.defaults.silenceThresholdDB }
        return timings
    }

    /// These timings with the fades back to their defaults.
    var withDefaultFades: TimingSettings {
        var timings = self
        timings.fadesEnabled = TimingSettings.defaults.fadesEnabled
        timings.fadeOutDuration = TimingSettings.defaults.fadeOutDuration
        timings.fadeInDuration = TimingSettings.defaults.fadeInDuration
        return timings
    }
}
