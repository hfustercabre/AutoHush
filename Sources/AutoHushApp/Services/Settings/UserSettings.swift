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
final class UserSettings: AutoPauseControlling {
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
    /// The timings as last logged, and the log of a change waiting for the
    /// slider to rest (`logTimingsOnceSettled`).
    @ObservationIgnored private var loggedTimings: TimingSettings
    @ObservationIgnored private var timingsLog: Task<Void, Never>?
    /// How long the timings must stay unchanged before their change is logged.
    @ObservationIgnored var timingsLogDelay: Duration = .seconds(1)
    private let logger = AutoHushLogger.settings

    /// An expired snooze is cleared at once.
    init(preferences: Preferences, now: Date = Date()) {
        self.preferences = preferences
        loggedTimings = preferences.timings
        state = State(seenApps: preferences.seenApps, ignoredApps: preferences.ignoredApps,
                      timings: preferences.timings, detection: preferences.detectionMethod,
                      listOrder: preferences.appListOrder)
        applyAutoPause(now: now)
    }

    // MARK: - Auto-Pause

    var isAutoPauseActive: Bool { state.autoPauseActive }

    var autoPauseSetting: AutoPauseSetting { preferences.autoPause }

    func toggleAutoPause(now: Date = Date()) {
        let isActive = preferences.autoPause.isActive(at: now)
        // Turning it on also ends a snooze; turning it off is indefinite.
        preferences.autoPause = AutoPauseSetting(isEnabled: !isActive, snoozedUntil: nil)
        logAutoPause()
        applyAutoPause(now: now)
    }

    func snooze(_ snooze: AutoPauseSnooze, now: Date = Date()) {
        preferences.autoPause = AutoPauseSetting(isEnabled: true, snoozedUntil: snooze.endDate(from: now))
        logAutoPause()
        applyAutoPause(now: now)
    }

    func setAutoPause(_ on: Bool) {
        preferences.autoPause = AutoPauseSetting(isEnabled: on, snoozedUntil: nil)
        logAutoPause()
        applyAutoPause()
    }

    /// Puts back a setting noted earlier, when a Focus with AutoHush's filter
    /// ends (`FocusAutoPause`); a "turn off for" that has run out comes back
    /// as on.
    func restoreAutoPause(_ setting: AutoPauseSetting, now: Date = Date()) {
        preferences.autoPause = setting
        logAutoPause(why: "a Focus ended")
        applyAutoPause(now: now)
    }

    private func logAutoPause(why: String? = nil) {
        let setting = preferences.autoPause
        let value = !setting.isEnabled ? "off"
            : setting.snoozedUntil.map { "off until \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "on"
        logger.info("Auto-Pause: \(value, privacy: .public)\(why.map { ", as \($0)" } ?? "", privacy: .public)")
    }

    /// Derives the effective Auto-Pause from the preferences, clearing an
    /// expired snooze, and schedules its next change.
    private func applyAutoPause(now: Date = Date()) {
        let setting = preferences.autoPause.clearingExpiredSnooze(at: now)
        if setting != preferences.autoPause {
            preferences.autoPause = setting
            logAutoPause(why: "its time ran out")
        }
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
        // Keep the app (with its icon) listed in Settings → Sound Sources, where it
        // was: switching it isn't playing.
        if source.bundlePath != nil { preferences.keepSeen(source) }
        var apps = preferences.ignoredApps.filter { $0.id != source.id }
        if apps.count == preferences.ignoredApps.count, ignored {
            logger.info("Ignored apps: added \(source.name, privacy: .public) (\(source.id, privacy: .public))")
        } else if apps.count != preferences.ignoredApps.count, !ignored {
            logger.info("Ignored apps: removed \(source.name, privacy: .public) (\(source.id, privacy: .public))")
        }
        if ignored { apps.append(AudioSource(id: source.id, name: source.name)) }
        storeIgnoredApps(apps)
    }

    /// Ignores an app the first time it's seen running (one that plays only
    /// the volume sound), as if the user had switched it off; once the user
    /// stops ignoring it, it stays so until the list is reset (`forgetAll`).
    func ignoreByDefault(_ source: AudioSource) {
        guard !preferences.appsIgnoredByDefault.contains(source.id) else { return }
        preferences.appsIgnoredByDefault.insert(source.id)
        guard !preferences.ignoredApps.contains(where: { $0.id == source.id }) else { return }
        logger.info("Ignored apps: \(source.name, privacy: .public) plays only the volume sound, so it’s ignored by default")
        setIgnored(source, true)
    }

    /// Removes an app from Settings → Sound Sources; a forgotten app is no longer ignored.
    func forget(_ source: AudioSource) {
        logger.info("Apps: removed \(source.name, privacy: .public) (\(source.id, privacy: .public)) from the list")
        preferences.seenApps.removeAll { $0.id == source.id }
        storeIgnoredApps(preferences.ignoredApps.filter { $0.id != source.id })
    }

    /// Empties Settings → Sound Sources: every app is forgotten and none is ignored
    /// any more. Apps reappear as they play audio; one AutoHush ignores by
    /// itself is ignored again the next time it runs (`ignoreByDefault`).
    func forgetAll() {
        logger.info("Apps: emptied the list, so no app is ignored")
        preferences.seenApps = []
        preferences.appsIgnoredByDefault = []
        storeIgnoredApps([])
    }

    func setListOrder(_ order: AppListOrder) {
        if order != state.listOrder {
            logger.info("Apps: ordered by \(order.criterion.rawValue, privacy: .public)\(order.isReversed ? ", reversed" : "", privacy: .public)")
        }
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
        logTimingsOnceSettled()
    }

    func setDetectionMethod(_ method: DetectionMethod) {
        if method != state.detection {
            logger.info("Detection: \(Self.name(of: state.detection), privacy: .public) → \(Self.name(of: method), privacy: .public)")
        }
        preferences.detectionMethod = method
        if method.isAntiDot { preferences.antiDotMethod = method }
        state.detection = method
    }

    /// AntiDot mode's way chosen last, which it's turned on with again.
    var antiDotMethod: DetectionMethod { preferences.antiDotMethod }

    /// A slider sets the timings at every step while it's dragged: their
    /// change is logged once, when they've stayed the same a moment.
    private func logTimingsOnceSettled() {
        timingsLog?.cancel()
        let delay = timingsLogDelay
        timingsLog = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            for change in Self.changes(from: loggedTimings, to: state.timings) {
                logger.info("\(change, privacy: .public)")
            }
            loggedTimings = state.timings
        }
    }

    /// Each timing that differs, as "<its name in Settings>: <old> → <new>".
    static func changes(from old: TimingSettings, to new: TimingSettings) -> [String] {
        func seconds(_ value: Double) -> String { "\(value.formatted(.number.precision(.fractionLength(0...2)))) s" }
        let rows: [(String, Double, Double, (Double) -> String)] = [
            ("Pause playback after", old.startConfirmation, new.startConfirmation, seconds),
            ("Resume playback after", old.stopGrace, new.stopGrace, seconds),
            ("Silence threshold", old.silenceThresholdDB, new.silenceThresholdDB, { "\(Int($0.rounded())) dBFS" }),
            ("Fade out before pausing", old.fadeOutDuration, new.fadeOutDuration, seconds),
            ("Fade in when resuming", old.fadeInDuration, new.fadeInDuration, seconds),
        ]
        var lines = rows.filter { $0.1 != $0.2 }.map { "\($0.0): \($0.3($0.1)) → \($0.3($0.2))" }
        if old.fadesEnabled != new.fadesEnabled { lines.append("Fade the music: \(new.fadesEnabled ? "on" : "off")") }
        if old.levelsMusic != new.levelsMusic { lines.append("Level the volume: \(new.levelsMusic ? "on" : "off")") }
        if old.staysPausedAfterCalls != new.staysPausedAfterCalls {
            lines.append("Stay paused after calls: \(new.staysPausedAfterCalls ? "on" : "off")")
        }
        return lines
    }

    /// A detection method, for the log.
    static func name(of method: DetectionMethod) -> String {
        switch method {
        case .audioLevels: "audio levels"
        case .playbackSignals: "AntiDot mode, by what apps say"
        case .openStreams: "AntiDot mode, by open sound"
        }
    }
}
