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
        var setTimings: @MainActor (TimingSettings) -> Void
        var setDetectionMethod: @MainActor (DetectionMethod) -> Void
        var setChecksForUpdates: @MainActor (Bool) -> Void
        var setAutomaticUpdates: @MainActor (AutomaticUpdates) -> Void
        var checkForUpdates: @MainActor () -> Void
        var openNotificationSettings: @MainActor () -> Void
    }

    /// One app in Settings → Apps, and whether it is ignored.
    struct AppRow: Identifiable, Equatable {
        let source: AudioSource
        let isIgnored: Bool
        var id: String { source.id }
    }

    // General
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginError: String?
    /// The music players to choose from (also in the welcome window).
    var playerOptions: [PlayerOption] = []
    /// The bundle ID of the chosen player; `nil` while none is chosen.
    var chosenPlayerID: String?
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
    var updateStatus: String?

    // Apps
    private(set) var apps: [AppRow] = []

    // Advanced
    var timings = TimingSettings.defaults

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
        launchAtLoginEnabled = launchAtLoginController.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        switch launchAtLoginController.setEnabled(enabled) {
        case .success:
            launchAtLoginError = nil
        case .failure(let error):
            launchAtLoginError = String(localized: "Could not change the login item: \(error.localizedDescription)",
                                        comment: "Settings, under Launch at login; %@ is the error macOS reported")
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    // MARK: - Forwarded actions

    func chooseMusicPlayer(_ bundleID: String) { actions.chooseMusicPlayer(bundleID) }
    func setAutoPause(_ on: Bool) { actions.setAutoPause(on) }
    func setPausesMusic(_ pauses: Bool, for source: AudioSource) { actions.setIgnored(source, !pauses) }
    func forget(_ source: AudioSource) { actions.forgetApp(source) }
    func forgetAllApps() { actions.forgetAllApps() }
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

    /// Apps that have played audio plus ignored apps, sorted by name.
    func setApps(seen: [AudioSource], ignored: [AudioSource]) {
        let ignoredIDs = Set(ignored.map(\.id))
        var sources = seen
        for app in ignored where !sources.contains(where: { $0.id == app.id }) {
            sources.append(app)
        }
        apps = sources
            .sortedByName()
            .map { AppRow(source: $0, isIgnored: ignoredIDs.contains($0.id)) }
    }
}
