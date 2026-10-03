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
        static let lastUpdateCheck = "lastUpdateCheck"
        static let detectionMethod = "detectionMethod"
        static let announcingApps = "announcingApps"
        /// Earlier on/off switch; `false` maps to `.openStreams`.
        static let legacyMeasuresAudioLevels = "measuresAudioLevels"
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
        ("resumeDelay", \.resumeDelay),
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

    package var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
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
