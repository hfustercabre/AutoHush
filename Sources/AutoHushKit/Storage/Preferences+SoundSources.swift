import Foundation

// Preferences: the apps for Settings → Sound Sources, seen and ignored.
extension Preferences {
    /// Apps that have played audio, most recent first (for Settings → Sound Sources).
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

    /// How Settings → Sound Sources orders its apps.
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

    /// The apps AutoHush once ignored by itself (`UserSettings.ignoreByDefault`),
    /// by bundle ID, ignored or not now: one the user stopped ignoring isn't
    /// ignored again, until the list is reset (`UserSettings.forgetAll`).
    package var appsIgnoredByDefault: Set<String> {
        get { Set(defaults.object(forKey: Key.appsIgnoredByDefault) as? [String] ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.appsIgnoredByDefault) }
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
