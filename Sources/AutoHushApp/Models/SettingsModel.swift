import Foundation
import Observation
import AutoHushKit

/// What the Settings window shows and edits, and the welcome, learning and
/// Add a Web App windows with it. It reads each part from its owner: what
/// the app's state holds (the chosen player, the status line, Auto-Pause,
/// learning and its pause) from `AppState`; the timings and detection from
/// `UserSettings`; the updates' settings and status from `updates`; the
/// chosen player's permissions from `PermissionCenter`; Settings → Sound
/// Sources' list from `appList`. The views' actions go to the modules that
/// own them (`settings`, `updates`, `learningSession`, `appList`), or to
/// `actions` for what only AppDelegate does. Launch at login is handled
/// here directly.
@MainActor
@Observable
final class SettingsModel {
    // General
    private(set) var launchAtLoginEnabled = false
    /// The menu bar icon is hidden (behind the notch): General says so
    /// under Keep icon next to system icons (the user, 2026-10-26).
    private(set) var menuBarIconHidden = false
    private(set) var launchAtLoginError: String?
    /// macOS waits for the user to allow AutoHush in Login Items.
    private(set) var launchAtLoginNeedsApproval = false
    /// The menu bar icon goes back beside the system's icons at each launch.
    private(set) var keepsMenuBarIconNearSystemIcons: Bool
    /// Whether AutoHush can fade the chosen player; the fade settings are
    /// dimmed when it can't.
    var playerCanFade: Bool { chosenPlayer?.canFade ?? true }

    /// What AutoHush needs for the chosen player, as last read; read again
    /// about once a second while a window that waits for it shows.
    var permissions: PermissionsState { permissionCenter.chosen }
    /// The welcome window shows what the chosen player needs, after its list.
    var welcomeAsksPermissions = false

    // From the app's state.
    /// The media players to choose from (also in the welcome window).
    var playerOptions: [PlayerOption] { state.playerOptions }
    /// The players as Settings → Media Player and the welcome window offer
    /// them: in AntiDot mode, the apps that can only be muted can't be chosen.
    var offeredPlayers: [PlayerOption] { playerOptions.inAntiDotMode(isAntiDotMode).offered }
    /// The bundle ID of the chosen player; `nil` while none is chosen.
    var chosenPlayerID: String? { state.chosenPlayerID }
    /// The chosen player as it's offered.
    var chosenPlayer: PlayerOption? { state.chosenPlayer }
    /// The chosen player's name, e.g. "Spotify".
    var chosenPlayerName: String? { chosenPlayer?.name }
    /// How far AutoHush has come learning to control the chosen player;
    /// `nil` for a player it controls without learning.
    var learning: LearningStatus? { state.learning }
    /// Its controls can be learned afresh (see `AppStatus`).
    var canLearnControlsAgain: Bool { state.canLearnControlsAgain }
    /// Once the user said the chosen player plays: when learning starts
    /// over without the pause.
    var learningPauseDeadline: Date? { state.learningPause.deadline }
    /// Why the user's last learning click didn't move it on.
    var learningNote: LearningNote? { state.learningPause.note }
    /// Once the user said it plays: AutoHush pauses it itself, to learn
    /// which button changes, or, when it couldn't, the user does.
    var learningPauseMode: LearningPauseMode { state.learningPause.mode }
    /// What the media player is doing, as the menu's card says it, e.g.
    /// "Paused — Safari is playing"; orange (`statusNeedsAttention`) when
    /// something needs the user.
    var statusLine: String { state.statusLine }
    var statusNeedsAttention: Bool { state.needsAttention }
    /// The chosen player needs reopening: the player card offers Reopen,
    /// as the menu's card does. The windows don't follow the whole status
    /// this is read from, so it's followed through the status line, which
    /// says so whenever it is ("Deezer needs reopening").
    var offersReopenPlayer: Bool {
        _ = state.statusLine
        return state.status.isReady && state.status.playerNeedsReopen
    }
    /// The chosen player is muted for another app: the player card offers
    /// Unmute, as the menu's card does. Followed as `offersReopenPlayer` is,
    /// through the status line, which says so ("Muted — …") while
    /// Auto-Pause is on.
    var offersUnmute: Bool {
        _ = state.statusLine
        return state.autoPause == .on && state.status.offersUnmute
    }
    /// "Couldn't resume", with Try Again, as the menu's card has it. Followed
    /// as `offersUnmute` is, through the status line.
    var showsResumeFailure: Bool {
        _ = state.statusLine
        return state.status.showsResumeFailure
    }
    /// The chosen player is muted now rather than paused (`AppStatus.mutesNow`):
    /// Sound Sources' apps say "Mutes your player". Followed through the
    /// chosen player (one that can only be muted) and, as `offersReopenPlayer`
    /// is, the status line, which says "Muted — …" while it's muted instead.
    var playerMutesNow: Bool {
        _ = (state.chosenPlayer, state.statusLine)
        return state.status.mutesNow
    }
    var isAutoPauseOn: Bool { state.autoPause == .on }
    /// E.g. "Turned off until 15:30.", shown under the auto-pause switch.
    var autoPauseNote: String? { state.autoPause.settingsNote }

    // From the user's settings.
    var detectionMethod: DetectionMethod { settings.state.detection }
    var timings: TimingSettings { settings.state.timings }

    // From the updates.
    var checksForUpdatesAutomatically: Bool { updates.checksAutomatically }
    /// What automatic checks lead to: notify, download or install.
    var automaticUpdates: AutomaticUpdates { updates.mode }
    /// Why AutoHush can't install updates itself, shown under the choice;
    /// nil when it can. Then only "Notify me" is possible. Read once, at launch.
    @ObservationIgnored let updateInstallNote: String?
    /// The choice About's pop-up shows, and explains in its help tag and
    /// hint: a copy that can't install itself can only notify, whatever was
    /// chosen before.
    var shownAutomaticUpdates: AutomaticUpdates { updateInstallNote == nil ? automaticUpdates : .notify }
    /// The user turned AutoHush's notifications off in System Settings. Then
    /// the update choices that rely on them are unavailable.
    var notificationsOff: Bool { updates.notificationsOff }
    /// What the last check from Settings found, e.g. "Checking…".
    var updateStatus: String? { updates.status }
    /// This copy's version, e.g. "0.3.11"; `nil` when unknown.
    var currentVersion: String? { updates.currentVersion?.description }
    /// The version with its build number, e.g. "0.6.1 (19)", for About and
    /// Diagnostics.
    var fullVersion: String? {
        fullVersion(build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    /// The same with `build` as this copy's build number: the version alone
    /// without one.
    func fullVersion(build: String?) -> String? {
        guard let currentVersion else { return nil }
        return build.map { "\(currentVersion) (\($0))" } ?? currentVersion
    }
    /// When updates were last checked for, by hand or automatically.
    var lastUpdateCheck: Date? { updates.lastCheck }

    // Sound Sources
    /// Its list: the rows, their order, the search, the selection and
    /// the removals.
    @ObservationIgnored let appList: AppListModel

    // Diagnostics
    /// What AutoHush sees, kept up to date while the Diagnostics tab shows.
    var diagnostics: DiagnosticsSnapshot?
    /// The parts of Diagnostics the user folded away; all open again each
    /// time Settings opens.
    var foldedDiagnostics: Set<DiagnosticsSnapshot.Part> = []
    /// The Fine-Tuning card a Behavior row asked for: Fine-Tuning opens
    /// scrolled to it, once.
    var fineTuningFocus: SettingsCard?
    /// The row was pressed with Return or Space: the arrow keys' highlight
    /// goes on from that card's first row (the user, 2026-10-25).
    var fineTuningFocusTakesHighlight = false

    /// Shows Fine-Tuning at `card`, one of its own (Behavior's rows, L4, the
    /// user's pick, 2026-10-25), its first row highlighted if `byKeyboard`.
    func showFineTuning(_ card: SettingsCard, byKeyboard: Bool = false) {
        fineTuningFocus = card
        fineTuningFocusTakesHighlight = byKeyboard
        actions?.openSettings(page: .fineTuning)
    }

    /// The row with Check Now: what the last check found ("AutoHush 0.3.11
    /// is up to date.", "Checking…"), or this version before any check.
    var updateTitle: String {
        updateStatus ?? currentVersion.map {
            String(localized: "AutoHush \($0)", comment: "Settings, beside Check Now before any check; %@ is the version")
        } ?? "AutoHush"
    }

    /// The row's title and the line under it: what a check in this launch
    /// found, with when the last one was; before one, only when the last one
    /// was, since About's header has the version (I2a, the user's pick,
    /// 2026-10-27: About showed it three times); before any check ever, this
    /// version.
    func updateRow(now: Date = Date()) -> (title: String, subtitle: String?) {
        let checked = lastCheckedNote(now: now)
        if updateStatus == nil, let checked { return (checked, nil) }
        return (updateTitle, checked)
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
    var isAntiDotMode: Bool { detectionMethod.isAntiDot }

    /// What the menu shows too, and learning's pause.
    @ObservationIgnored let state: AppState
    /// The user's settings: Settings shows some of them from there, and
    /// changes them there.
    @ObservationIgnored let settings: UserSettings
    /// Update checks, and their settings.
    @ObservationIgnored let updates: any UpdateCommands
    /// Reads the permissions; Settings shows the chosen player's as last read.
    @ObservationIgnored let permissionCenter: PermissionCenter
    /// Learning the chosen web app's controls: its windows' steps.
    @ObservationIgnored let learningSession: LearningSession
    /// What only AppDelegate does: choosing a player, its windows, the
    /// permissions.
    @ObservationIgnored weak var actions: any AppActions?
    @ObservationIgnored private let launchAtLoginController: any LaunchAtLoginControlling
    @ObservationIgnored private let menuBarIcon: MenuBarIconPlace

    init(state: AppState = AppState(), settings: UserSettings, updates: any UpdateCommands,
         permissionCenter: PermissionCenter = PermissionCenter(),
         learningSession: LearningSession = LearningSession(), actions: any AppActions?,
         launchAtLoginController: any LaunchAtLoginControlling,
         menuBarIcon: MenuBarIconPlace = MenuBarIconPlace(defaults: .standard)) {
        self.state = state
        self.settings = settings
        self.updates = updates
        updateInstallNote = updates.installUnavailability?.explanation
        self.permissionCenter = permissionCenter
        self.learningSession = learningSession
        self.actions = actions
        self.launchAtLoginController = launchAtLoginController
        self.menuBarIcon = menuBarIcon
        keepsMenuBarIconNearSystemIcons = menuBarIcon.keepsNearSystemIcons
        appList = AppListModel(state: state, settings: settings)
        refreshLaunchAtLogin()
    }

    // MARK: - Launch at login

    func refreshLaunchAtLogin() {
        let enabled = launchAtLoginController.isEnabled, needsApproval = launchAtLoginController.needsApproval
        // Changed meanwhile (System Settings → Login Items): an error from
        // before no longer stands (the workflow audit, 2026-10-22).
        if launchAtLoginEnabled != enabled || launchAtLoginNeedsApproval != needsApproval { launchAtLoginError = nil }
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

    // MARK: - Menu bar icon

    /// Turned on, the icon moves beside the system's icons at once.
    func setKeepsMenuBarIconNearSystemIcons(_ keeps: Bool) {
        menuBarIcon.keepsNearSystemIcons = keeps
        keepsMenuBarIconNearSystemIcons = keeps
        if keeps { actions?.moveMenuBarIconNearSystemIcons() }
        refreshMenuBarIcon()
    }

    /// Whether the menu bar icon is hidden, read again: as Settings opens,
    /// once the switch moved the icon, and each time macOS moves its window
    /// (`StatusMenuController.followItemMoves`).
    func refreshMenuBarIcon() {
        let hidden = actions?.menuBarIconIsHidden ?? false
        if menuBarIconHidden != hidden { menuBarIconHidden = hidden }
    }

    // MARK: - Choices

    /// Back to the welcome window's list, to choose another player.
    func showWelcomePlayers() { welcomeAsksPermissions = false }

    /// AntiDot mode doesn't need Audio Recording: the way past it without
    /// allowing it, in its way chosen last.
    func useAntiDotMode() { setDetectionMethod(settings.antiDotMethod) }

    func setTimings(_ timings: TimingSettings) {
        settings.setTimings(timings.clamped)
    }

    /// AntiDot mode isn't turned on while the player can only be muted,
    /// which AntiDot mode can't do (its switch is off and dimmed then).
    func setDetectionMethod(_ method: DetectionMethod) {
        if method.isAntiDot, !isAntiDotMode, antiDotUnavailableFor != nil { return }
        settings.setDetectionMethod(method)
    }

    /// The chosen player's name, when only its sound tells how it is (an app
    /// added with Add an App, muted only or controlled through a Now Playing
    /// row that doesn't follow it): AntiDot mode can't be turned on while
    /// it's the player.
    var antiDotUnavailableFor: String? {
        antiDotUnavailablePlayer?.name
    }

    /// The media player, when only its sound tells how it is
    /// (`PlayerOption.needsAudioLevels`): AntiDot mode can't be used with it.
    /// Read from the chosen player as it's followed, so a player checked
    /// again (the same app, muted now) updates the switch.
    var antiDotUnavailablePlayer: PlayerOption? {
        chosenPlayer.flatMap { $0.needsAudioLevels ? $0 : nil }
    }

    /// On: in its way chosen last, by what apps tell macOS until one is
    /// chosen (the indicator-free method that keeps the most accuracy).
    /// Off: measures audio levels.
    func setAntiDotMode(_ on: Bool) {
        guard on != isAntiDotMode else { return }
        setDetectionMethod(on ? settings.antiDotMethod : .audioLevels)
    }
}
