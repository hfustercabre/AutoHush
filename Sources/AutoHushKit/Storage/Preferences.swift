import Foundation

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
        static let detectionMethod = "detectionMethod"
        static let announcingApps = "announcingApps"
        /// Earlier on/off switch; `false` maps to `.openStreams`.
        static let legacyMeasuresAudioLevels = "measuresAudioLevels"
        static let musicPlayer = "musicPlayer"
        /// Set once the music player could be chosen (see `keepFormerPlayer`).
        static let playerChoiceIntroduced = "playerChoiceIntroduced"
        /// Kept by any earlier AutoHush that ran on this Mac.
        static let earlierVersionKeys = [
            lastLaunchedVersion, lastUpdateCheck, seenApps, ignoredApps, autoPauseEnabled, timings,
            detectionMethod, legacyMeasuresAudioLevels, checksForUpdates, automaticUpdates, legacyInstallsUpdates,
        ]
    }

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
    private static let timingKeys: [(key: String, value: WritableKeyPath<TimingSettings, Double>)] = [
        ("startConfirmation", \.startConfirmation),
        ("stopGrace", \.stopGrace),
        ("silenceThresholdDB", \.silenceThresholdDB),
        ("fadeOutDuration", \.fadeOutDuration),
        ("fadeInDuration", \.fadeInDuration),
    ]

    package var timings: TimingSettings {
        get {
            let stored = defaults.object(forKey: Key.timings) as? [String: Double] ?? [:]
            var timings = TimingSettings.defaults
            for (key, value) in Self.timingKeys {
                if let number = stored[key] { timings[keyPath: value] = number }
            }
            return timings.clamped
        }
        set {
            let value = newValue.clamped
            let stored = Dictionary(uniqueKeysWithValues: Self.timingKeys.map { ($0.key, value[keyPath: $0.value]) })
            defaults.set(stored, forKey: Key.timings)
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

    /// Apps seen announcing playback with a power assertion (AntiDot mode).
    package var announcingApps: Set<String> {
        get { Set(defaults.object(forKey: Key.announcingApps) as? [String] ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.announcingApps) }
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

    /// When AutoHush last quit to install an update while holding the music
    /// paused; the new version takes that pause over.
    package var pauseHandedOverAt: Date? {
        get { defaults.object(forKey: Key.pauseHandedOver) as? Date }
        set { defaults.set(newValue, forKey: Key.pauseHandedOver) }
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
