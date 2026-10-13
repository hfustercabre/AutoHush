import Foundation
import Observation
import AutoHushKit

/// The user's own settings and what follows from them (see GLOSSARY.md):
/// Auto-Pause and its snooze, the apps ignored and the apps seen, the
/// timings, the detection method, the order of Settings' list of apps. It
/// stores them in `Preferences`; the menu, Settings and the monitoring show
/// or follow its state. Settings reads what only it shows (the timings,
/// detection and the list's order) here; the rest through the app state.
@MainActor
@Observable
final class UserSettings {
    /// What the menu, Settings and the monitoring show or follow of it.
    struct State: Equatable {
        /// Auto-Pause as the menu and Settings say it: on, off, or off until.
        var autoPause = AppStatus.AutoPause.on
        /// Auto-Pause is on now (neither off nor snoozed): the monitoring
        /// follows this.
        var autoPauseActive = true
        /// The apps that played sound, the most recent first.
        var seenApps: [AudioSource] = []
        /// The apps the user ignores: they never pause the player.
        var ignoredApps: [AudioSource] = []
        var timings = TimingSettings.defaults
        var detection = DetectionMethod.audioLevels
        /// How Settings orders its list of apps.
        var listOrder = AppListOrder.standard

        /// What the chosen player's monitoring follows.
        var monitoring: MonitoringSettings {
            MonitoringSettings(autoPause: autoPauseActive, ignored: Set(ignoredApps.map(\.id)),
                               timings: timings, detection: detection)
        }
    }

    private(set) var state = State() {
        didSet { if state != oldValue { didChange(state) } }
    }
    /// Called each time `state` changes.
    @ObservationIgnored var didChange: @MainActor (State) -> Void = { _ in }

    @ObservationIgnored private let preferences: Preferences
    /// When the menu's words for a snooze change next: its end, or midnight
    /// before it ("until tomorrow 8:00" becomes "until 8:00").
    @ObservationIgnored private var snoozeTimer: Timer?

    /// An expired snooze is cleared at once.
    init(preferences: Preferences, now: Date = Date()) {
        self.preferences = preferences
        state = State(seenApps: preferences.seenApps, ignoredApps: preferences.ignoredApps,
                      timings: preferences.timings, detection: preferences.detectionMethod,
                      listOrder: preferences.appListOrder)
        applyAutoPause(now: now)
    }

    // MARK: - Auto-Pause

    func toggleAutoPause(now: Date = Date()) {
        let isActive = preferences.autoPause.isActive(at: now)
        // Turning it on also ends a snooze; turning it off is indefinite.
        preferences.autoPause = AutoPauseSetting(isEnabled: !isActive, snoozedUntil: nil)
        applyAutoPause(now: now)
    }

    func snooze(_ snooze: AutoPauseSnooze, now: Date = Date()) {
        preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: snooze.endDate(from: now))
        applyAutoPause(now: now)
    }

    func setAutoPause(_ on: Bool) {
        preferences.autoPause = AutoPauseSetting(isEnabled: on, snoozedUntil: nil)
        applyAutoPause()
    }

    /// Derives the effective Auto-Pause from the preferences, clearing an
    /// expired snooze, and schedules its next change.
    private func applyAutoPause(now: Date = Date()) {
        let setting = preferences.autoPause.clearingExpiredSnooze(at: now)
        if setting != preferences.autoPause { preferences.autoPause = setting }
        var next = state
        next.autoPause = AppStatus.AutoPause(setting, now: now)
        next.autoPauseActive = setting.isActive(at: now)
        state = next
        let snoozeEnd = setting.isEnabled ? setting.snoozedUntil : nil
        scheduleAutoPauseUpdate(at: snoozeEnd.map { AppStatus.AutoPause.nextChange(snoozedUntil: $0, now: now) })
    }

    /// Applies Auto-Pause again at `date`: when the snooze ends, or at
    /// midnight (`nil`: no snooze).
    private func scheduleAutoPauseUpdate(at date: Date?) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyAutoPause() }
        }
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }

    // MARK: - The apps

    func setIgnored(_ source: AudioSource, _ ignored: Bool) {
        // Keep the app (with its icon) listed in Settings → Apps, where it
        // was: switching it isn't playing.
        if source.bundlePath != nil { preferences.keepSeen(source) }
        var apps = preferences.ignoredApps.filter { $0.id != source.id }
        if ignored { apps.append(AudioSource(id: source.id, name: source.name)) }
        storeIgnoredApps(apps)
    }

    /// Removes an app from Settings → Apps; a forgotten app is no longer ignored.
    func forget(_ source: AudioSource) {
        preferences.seenApps.removeAll { $0.id == source.id }
        storeIgnoredApps(preferences.ignoredApps.filter { $0.id != source.id })
    }

    /// Empties Settings → Apps: every app is forgotten and none is ignored
    /// any more. Apps reappear as they play audio.
    func forgetAll() {
        preferences.seenApps = []
        storeIgnoredApps([])
    }

    func setListOrder(_ order: AppListOrder) {
        preferences.appListOrder = order
        state.listOrder = order
    }

    /// The monitoring recorded the apps it heard play (`Preferences.recordSeen`).
    func appsSeenChanged() {
        state.seenApps = preferences.seenApps
    }

    private func storeIgnoredApps(_ apps: [AudioSource]) {
        preferences.ignoredApps = apps
        var next = state
        next.seenApps = preferences.seenApps
        next.ignoredApps = apps
        state = next
    }

    // MARK: - Detection

    func setTimings(_ timings: TimingSettings) {
        preferences.timings = timings
        state.timings = preferences.timings
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        preferences.detectionMethod = method
        state.detection = method
    }
}
