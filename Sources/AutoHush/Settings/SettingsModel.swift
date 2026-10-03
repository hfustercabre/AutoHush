import Foundation
import Observation

/// What the Settings window shows and edits. `AppDelegate` keeps it in sync
/// with the app's state and performs the actions; launch at login is handled
/// here directly.
@MainActor
@Observable
final class SettingsModel {
    struct Actions {
        var setAutoPause: @MainActor (Bool) -> Void
        var setIgnored: @MainActor (AudioSource, Bool) -> Void
        var forgetApp: @MainActor (AudioSource) -> Void
        var forgetAllApps: @MainActor () -> Void
        var setTimings: @MainActor (TimingSettings) -> Void
        var setDetectionMethod: @MainActor (DetectionMethod) -> Void
        var setChecksForUpdates: @MainActor (Bool) -> Void
        var checkForUpdates: @MainActor () -> Void
    }

    struct AppRow: Identifiable, Equatable {
        let source: AudioSource
        let isIgnored: Bool
        var id: String { source.id }
    }

    // General
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginError: String?
    var isAutoPauseOn = true
    /// E.g. "Turned off until 15:30.", shown under the auto-pause switch.
    var autoPauseNote: String?
    var detectionMethod = DetectionMethod.audioLevels
    var checksForUpdatesAutomatically = true
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
            launchAtLoginError = "Could not change the login item: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        launchAtLoginController.openSystemSettings()
    }

    // MARK: - Forwarded actions

    func setAutoPause(_ on: Bool) { actions.setAutoPause(on) }
    func setPausesMusic(_ pauses: Bool, for source: AudioSource) { actions.setIgnored(source, !pauses) }
    func forget(_ source: AudioSource) { actions.forgetApp(source) }
    func forgetAllApps() { actions.forgetAllApps() }
    func setChecksForUpdates(_ on: Bool) { actions.setChecksForUpdates(on) }
    func checkForUpdates() { actions.checkForUpdates() }

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
