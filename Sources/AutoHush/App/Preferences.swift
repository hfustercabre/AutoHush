import Foundation

/// Where preferences are kept: `UserDefaults` in the app, memory in tests.
protocol PreferenceStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

/// User choices that persist across launches, stored in `UserDefaults`.
@MainActor
final class Preferences {
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
    static let seenAppsLimit = 50

    private let defaults: any PreferenceStore

    init(store: any PreferenceStore = UserDefaults.standard) {
        self.defaults = store
    }

    var autoPause: AutoPauseSetting {
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

    var timings: TimingSettings {
        get {
            guard let stored = defaults.object(forKey: Key.timings) as? [String: Double] else { return .defaults }
            let defaults = TimingSettings.defaults
            return TimingSettings(
                startConfirmation: stored["startConfirmation"] ?? defaults.startConfirmation,
                stopGrace: stored["stopGrace"] ?? defaults.stopGrace,
                resumeDelay: stored["resumeDelay"] ?? defaults.resumeDelay,
                silenceThresholdDB: stored["silenceThresholdDB"] ?? defaults.silenceThresholdDB
            ).clamped
        }
        set {
            let value = newValue.clamped
            defaults.set([
                "startConfirmation": value.startConfirmation,
                "stopGrace": value.stopGrace,
                "resumeDelay": value.resumeDelay,
                "silenceThresholdDB": value.silenceThresholdDB,
            ], forKey: Key.timings)
        }
    }

    /// Settings → General → AntiDot mode and its detection choice.
    var detectionMethod: DetectionMethod {
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
    var announcingApps: Set<String> {
        get { Set(defaults.object(forKey: Key.announcingApps) as? [String] ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.announcingApps) }
    }

    var checksForUpdatesAutomatically: Bool {
        get { defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.checksForUpdates) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Key.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    /// Apps that have played audio, most recent first (for Settings → Apps).
    var seenApps: [AudioSource] {
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
    func recordSeen(_ apps: [AudioSource]) {
        guard !apps.isEmpty else { return }
        let ids = Set(apps.map(\.id))
        let current = seenApps
        let updated = apps + current.filter { !ids.contains($0.id) }
        if updated != current { seenApps = updated }
    }

    /// Apps that never pause Spotify, sorted by name.
    var ignoredApps: [AudioSource] {
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
