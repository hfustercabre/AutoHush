import Foundation

// Preferences: the update checks and downloads, and the version that ran last.
extension Preferences {
    package var checksForUpdatesAutomatically: Bool {
        get { defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.checksForUpdates) }
    }

    /// Update checks look for release candidates too (off by default).
    package var getsReleaseCandidates: Bool {
        get { defaults.object(forKey: Key.getsReleaseCandidates) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.getsReleaseCandidates) }
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
}
