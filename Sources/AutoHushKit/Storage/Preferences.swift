import Foundation
import os

/// Where preferences are kept: `UserDefaults` in the app, memory in tests.
package protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

/// User choices that persist across launches, stored in `UserDefaults`.
@MainActor
package final class Preferences {
    private enum Key {
        static let autoPauseEnabled = "autoPauseEnabled"
        static let autoPauseSnoozedUntil = "autoPauseSnoozedUntil"
        static let ignoredApps = "ignoredApps"
        static let seenApps = "seenApps"
        static let appListOrder = "appListOrder"
        static let appListOrderReversed = "appListOrderReversed"
        static let timings = "timings"
        static let checksForUpdates = "checksForUpdatesAutomatically"
        static let automaticUpdates = "automaticUpdates"
        /// Earlier on/off switch; `false` maps to `.notify`.
        static let legacyInstallsUpdates = "installsUpdatesAutomatically"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let downloadedUpdate = "downloadedUpdate"
        static let expiredUpdateVersion = "expiredUpdateVersion"
        static let lastUpdateNotice = "lastUpdateNotice"
        static let lastLaunchedVersion = "lastLaunchedVersion"
        static let pauseHandedOver = "pauseHandedOverAt"
        static let pauseHandedOverPlayer = "pauseHandedOverPlayer"
        static let detectionMethod = "detectionMethod"
        static let playbackAssertions = "playbackAssertions"
        /// Earlier list of apps seen announcing playback, without the names
        /// AntiDot mode now learns; dropped, so apps are learned again.
        static let legacyAnnouncingApps = "announcingApps"
        /// Earlier on/off switch; `false` maps to `.openStreams`.
        static let legacyMeasuresAudioLevels = "measuresAudioLevels"
        static let musicPlayer = "musicPlayer"
        static let webAppButtons = Preferences.webAppButtonsKey
        /// Set once the music player could be chosen (see `keepFormerPlayer`).
        static let playerChoiceIntroduced = "playerChoiceIntroduced"
        /// Kept by any earlier AutoHush that ran on this Mac.
        static let earlierVersionKeys = [
            lastLaunchedVersion, lastUpdateCheck, seenApps, ignoredApps, autoPauseEnabled, timings,
            detectionMethod, legacyMeasuresAudioLevels, checksForUpdates, automaticUpdates, legacyInstallsUpdates,
        ]
    }

    /// Each web app's learned Play/Pause button, by its bundle ID. The
    /// players read and save theirs from their own queues (`UserDefaults` is
    /// thread-safe); this class only clears out old ones.
    package nonisolated static let webAppButtonsKey = "webAppPlayPauseButtons"
    /// Every change to them holds this lock: a change reads them all, then
    /// writes them all back, from several queues.
    package nonisolated static let webAppButtonsLock = OSAllocatedUnfairLock()

    /// How many apps that played audio are remembered for Settings → Apps.
    package static let seenAppsLimit = 50

    private let defaults: any PreferenceStore

    package init(store: any PreferenceStore = UserDefaults.standard) {
        self.defaults = store
    }

    package var autoPause: AutoPauseSetting {
        get {
            AutoPauseSetting(
                isEnabled: defaults.object(forKey: Key.autoPauseEnabled) as? Bool ?? true,
                snoozedUntil: defaults.object(forKey: Key.autoPauseSnoozedUntil) as? Date
            )
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Key.autoPauseEnabled)
            defaults.set(newValue.snoozedUntil, forKey: Key.autoPauseSnoozedUntil)
        }
    }

    /// Each timing's key in the stored dictionary. A missing key keeps its default.
    /// Whether fades are on is stored there too, as 1 or 0 (`fadesEnabledKey`).
    private static let timingKeys: [(key: String, value: WritableKeyPath<TimingSettings, Double>)] = [
        ("startConfirmation", \.startConfirmation),
        ("stopGrace", \.stopGrace),
        ("silenceThresholdDB", \.silenceThresholdDB),
        ("fadeOutDuration", \.fadeOutDuration),
        ("fadeInDuration", \.fadeInDuration),
    ]
    private static let fadesEnabledKey = "fadesEnabled"

    package var timings: TimingSettings {
        get {
            let stored = defaults.object(forKey: Key.timings) as? [String: Double] ?? [:]
            var timings = TimingSettings.defaults
            for (key, value) in Self.timingKeys {
                if let number = stored[key] { timings[keyPath: value] = number }
            }
            if let enabled = stored[Self.fadesEnabledKey] { timings.fadesEnabled = enabled != 0 }
            return timings.clamped
        }
        set {
            let value = newValue.clamped
            var stored = Dictionary(uniqueKeysWithValues: Self.timingKeys.map { ($0.key, value[keyPath: $0.value]) })
            stored[Self.fadesEnabledKey] = value.fadesEnabled ? 1 : 0
            defaults.set(stored, forKey: Key.timings)
        }
    }

    /// Forgets the learned buttons of web apps for which `isGone` is true
    /// (deleted: adding a site again makes a new app, with a new ID).
    package func forgetWebAppButtons(where isGone: (String) -> Bool) {
        Self.webAppButtonsLock.withLockUnchecked {
            guard let stored = defaults.object(forKey: Key.webAppButtons) as? [String: Any] else { return }
            let kept = stored.filter { !isGone($0.key) }
            if kept.count != stored.count { defaults.set(kept, forKey: Key.webAppButtons) }
        }
    }

    /// The bundle ID of the music player AutoHush controls; `nil` until the
    /// user chooses one.
    package var musicPlayer: String? {
        get { defaults.object(forKey: Key.musicPlayer) as? String }
        set { defaults.set(newValue, forKey: Key.musicPlayer) }
    }

    /// AutoHush controlled one player before it could be chosen. On the first
    /// launch of a version with the choice, someone updating (an earlier
    /// AutoHush left its settings) keeps that player instead of being asked.
    /// Call it before anything else is stored at launch. Later launches leave
    /// the choice alone, so a new user who hasn't chosen yet is still asked.
    package func keepFormerPlayer(_ bundleID: String?) {
        guard defaults.object(forKey: Key.playerChoiceIntroduced) == nil else { return }
        defaults.set(true, forKey: Key.playerChoiceIntroduced)
        guard musicPlayer == nil, let bundleID,
              Key.earlierVersionKeys.contains(where: { defaults.object(forKey: $0) != nil })
        else { return }
        musicPlayer = bundleID
    }

    /// Settings → General → AntiDot mode and its detection choice.
    package var detectionMethod: DetectionMethod {
        get {
            if let stored = (defaults.object(forKey: Key.detectionMethod) as? String).flatMap(DetectionMethod.init) {
                return stored
            }
            return defaults.object(forKey: Key.legacyMeasuresAudioLevels) as? Bool == false ? .openStreams : .audioLevels
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.detectionMethod)
            defaults.set(nil, forKey: Key.legacyMeasuresAudioLevels)
        }
    }

    /// What AntiDot mode learned about how apps tell macOS they play: the
    /// names of the power assertions each app held while its sound was on.
    package var playbackAssertions: [String: AnnouncedAssertions] {
        get {
            let stored = defaults.object(forKey: Key.playbackAssertions) as? [String: [String: [String]]] ?? [:]
            return stored.mapValues { AnnouncedAssertions(system: Set($0["system"] ?? []), display: Set($0["display"] ?? [])) }
        }
        set {
            let stored = newValue.mapValues { ["system": $0.system.sorted(), "display": $0.display.sorted()] }
            defaults.set(stored, forKey: Key.playbackAssertions)
            defaults.set(nil, forKey: Key.legacyAnnouncingApps)
        }
    }

    package var checksForUpdatesAutomatically: Bool {
        get { defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.checksForUpdates) }
    }

    /// What happens when an automatic check finds a newer version. Before the
    /// choice existed, "install updates automatically" was on or off.
    package var automaticUpdates: AutomaticUpdates {
        get {
            if let stored = (defaults.object(forKey: Key.automaticUpdates) as? String).flatMap(AutomaticUpdates.init) {
                return stored
            }
            return defaults.object(forKey: Key.legacyInstallsUpdates) as? Bool == false ? .notify : .install
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.automaticUpdates)
            defaults.set(nil, forKey: Key.legacyInstallsUpdates)
        }
    }

    package var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    /// The update downloaded and kept until it's installed.
    package var downloadedUpdate: DownloadedUpdate? {
        get {
            let stored = defaults.object(forKey: Key.downloadedUpdate) as? [String: Any]
            guard let version = stored?["version"] as? String, let sha256 = stored?["sha256"] as? String,
                  let downloadedAt = stored?["downloadedAt"] as? Date
            else { return nil }
            return DownloadedUpdate(version: version, sha256: sha256, downloadedAt: downloadedAt)
        }
        set {
            let stored = newValue.map { ["version": $0.version, "sha256": $0.sha256, "downloadedAt": $0.downloadedAt] as [String: Any] }
            defaults.set(stored, forKey: Key.downloadedUpdate)
        }
    }

    /// A version whose download was deleted unused after a week; it isn't
    /// downloaded again automatically.
    package var expiredUpdateVersion: String? {
        get { defaults.object(forKey: Key.expiredUpdateVersion) as? String }
        set { defaults.set(newValue, forKey: Key.expiredUpdateVersion) }
    }

    /// The last update notification sent, e.g. "available 0.3.8", so none is
    /// sent twice.
    package var lastUpdateNotice: String? {
        get { defaults.object(forKey: Key.lastUpdateNotice) as? String }
        set { defaults.set(newValue, forKey: Key.lastUpdateNotice) }
    }

    /// The version that ran last, to tell after an update that it happened.
    package var lastLaunchedVersion: String? {
        get { defaults.object(forKey: Key.lastLaunchedVersion) as? String }
        set { defaults.set(newValue, forKey: Key.lastLaunchedVersion) }
    }

    /// The pause AutoHush last handed over when it quit while holding the
    /// music paused (to install an update, say); the next AutoHush takes it
    /// over.
    package var pauseHandover: PauseHandover? {
        get {
            guard let at = defaults.object(forKey: Key.pauseHandedOver) as? Date else { return nil }
            // AutoHush 0.8.2 and earlier write the date alone and leave the
            // player as it was: it's this pause's only if written with it.
            let named = defaults.object(forKey: Key.pauseHandedOverPlayer) as? [String: Any]
            let namedAt = named?["at"] as? Date
            let isThisPause = namedAt.map { abs($0.timeIntervalSince(at)) < 1 } ?? false
            return PauseHandover(at: at, player: isThisPause ? named?["player"] as? String : nil)
        }
        set {
            defaults.set(newValue?.at, forKey: Key.pauseHandedOver)
            let named: [String: Any]? = newValue.flatMap { handover in
                handover.player.map { ["at": handover.at, "player": $0] }
            }
            defaults.set(named, forKey: Key.pauseHandedOverPlayer)
        }
    }

    /// Apps that have played audio, most recent first (for Settings → Apps).
    package var seenApps: [AudioSource] {
        get {
            let stored = defaults.object(forKey: Key.seenApps) as? [[String: String]] ?? []
            return stored.compactMap { entry in
                guard let id = entry["id"], let name = entry["name"] else { return nil }
                return AudioSource(id: id, name: name, bundlePath: entry["path"])
            }
        }
        set {
            let stored = newValue.prefix(Self.seenAppsLimit).map { app -> [String: String] in
                var entry = ["id": app.id, "name": app.name]
                entry["path"] = app.bundlePath
                return entry
            }
            defaults.set(Array(stored), forKey: Key.seenApps)
        }
    }

    /// Moves the apps to the front of `seenApps`, keeping each app once.
    package func recordSeen(_ apps: [AudioSource]) {
        guard !apps.isEmpty else { return }
        let ids = Set(apps.map(\.id))
        let current = seenApps
        let updated = apps + current.filter { !ids.contains($0.id) }
        if updated != current { seenApps = updated }
    }

    /// Adds the app to `seenApps`, at the front, unless it's there already:
    /// unlike `recordSeen`, it doesn't count as having just played.
    package func keepSeen(_ app: AudioSource) {
        guard !seenApps.contains(where: { $0.id == app.id }) else { return }
        seenApps = [app] + seenApps
    }

    /// How Settings → Apps orders its apps.
    package var appListOrder: AppListOrder {
        get {
            let criterion = (defaults.object(forKey: Key.appListOrder) as? String).flatMap(AppListOrder.Criterion.init)
            return AppListOrder(
                criterion: criterion ?? AppListOrder.standard.criterion,
                isReversed: defaults.object(forKey: Key.appListOrderReversed) as? Bool ?? false
            )
        }
        set {
            defaults.set(newValue.criterion.rawValue, forKey: Key.appListOrder)
            defaults.set(newValue.isReversed, forKey: Key.appListOrderReversed)
        }
    }

    /// Apps that never pause the music, sorted by name.
    package var ignoredApps: [AudioSource] {
        get {
            let stored = defaults.object(forKey: Key.ignoredApps) as? [String: String] ?? [:]
            return stored
                .map { AudioSource(id: $0.key, name: $0.value) }
                .sortedByName()
        }
        set {
            let stored = Dictionary(newValue.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
            defaults.set(stored, forKey: Key.ignoredApps)
        }
    }
}
