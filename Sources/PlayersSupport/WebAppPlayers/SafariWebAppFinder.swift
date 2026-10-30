import AppKit
import os
import AutoHushKit

/// Finds the Safari web apps in the Applications folders (not in folders
/// inside them, where Safari never puts them). An app's Info.plist is read
/// again only when it changed, and a look less than `maxAge` old is reused
/// (offering the players looks twice in a row), so looking often costs
/// little.
package final class SafariWebAppFinder: Sendable {
    private let folders: [URL]
    /// What each app's Info.plist said, by the app's path, with the date it
    /// was changed then.
    private let cache = OSAllocatedUnfairLock<[String: (changed: Date, app: SafariWebApp?)]>(initialState: [:])
    /// The last look's result, and when.
    private let lastLook = OSAllocatedUnfairLock<(at: Date, apps: [SafariWebApp])?>(initialState: nil)

    /// `folders`: the current user's Applications folder and /Applications.
    package init(folders: [URL] = ApplicationFolders.forWebApps) {
        self.folders = folders
    }

    /// The web apps installed now, by name; from a look at most `maxAge`
    /// old (0 looks afresh).
    package func webApps(maxAge: TimeInterval = 1) -> [SafariWebApp] {
        let now = Date()
        if let last = lastLook.withLock({ $0 }), now.timeIntervalSince(last.at) < maxAge { return last.apps }
        let apps = look()
        lastLook.withLock { [apps] in $0 = (now, apps) }
        return apps
    }

    private func look() -> [SafariWebApp] {
        let fileManager = FileManager.default
        var found: [String: (changed: Date, app: SafariWebApp?)] = [:]
        let known = cache.withLock { $0 }
        for folder in folders {
            let apps = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in apps where url.pathExtension == "app" {
                let plist = url.appending(path: "Contents/Info.plist").path
                guard let changed = (try? fileManager.attributesOfItem(atPath: plist))?[.modificationDate] as? Date
                else { continue }
                if let entry = known[url.path], entry.changed == changed {
                    found[url.path] = entry
                } else {
                    found[url.path] = (changed, SafariWebApp(bundleAt: url))
                }
            }
        }
        cache.withLock { [found] in $0 = found }
        var seen: Set<String> = []
        return found.values.compactMap(\.app)
            .sorted { ($0.name.localizedLowercase, $0.url.path) < ($1.name.localizedLowercase, $1.url.path) }
            .filter { seen.insert($0.bundleID).inserted } // a copy in both folders is offered once
    }
}
