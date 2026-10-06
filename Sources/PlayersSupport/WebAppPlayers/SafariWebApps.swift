import AppKit
import os
import AutoHushKit

/// A website added to the Dock from Safari (File → Add to Dock). Each is an
/// app of its own, `com.apple.Safari.WebApp.<UUID>`, usually in
/// ~/Applications, that Safari's one "Web App" program runs: a template app
/// with no program inside, only its Info.plist and icon.
package struct SafariWebApp: Equatable, Sendable {
    package let bundleID: String
    /// The name it's offered under (see `shortName`).
    package let name: String
    /// Where it's installed.
    package let url: URL

    /// Every Safari web app's bundle ID starts with it.
    package static let bundleIDPrefix = "com.apple.Safari.WebApp."

    package init(bundleID: String, name: String, url: URL) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }

    /// The web app in the bundle at `url`; `nil` for any other app.
    package init?(bundleAt url: URL) {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID.hasPrefix(Self.bundleIDPrefix)
        else { return nil }
        let name = (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        self.init(bundleID: bundleID, name: Self.shortName(name), url: url)
    }

    /// A web app is named after the page's title, which often adds a slogan
    /// after " | ": "Amazon Music Unlimited | Escucha millones de canciones"
    /// is offered as "Amazon Music Unlimited".
    package static func shortName(_ name: String) -> String {
        let short = name.components(separatedBy: " | ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return short.isEmpty ? name : short
    }

    /// The web app a running process is, so its sound is told apart from the
    /// other web apps' (they all run the same program); `nil` for any other
    /// process.
    package static func source(forProcess pid: pid_t) -> AudioSource? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier?.hasPrefix(bundleIDPrefix) == true,
              let url = app.bundleURL,
              let webApp = SafariWebApp(bundleAt: url)
        else { return nil }
        return AudioSource(id: webApp.bundleID, name: webApp.name, bundlePath: url.path)
    }
}

/// Finds the Safari web apps in the Applications folders (not in folders
/// inside them, where Safari never puts them). An app's Info.plist is read
/// again only when it changed, so looking often costs little.
package final class SafariWebAppFinder: Sendable {
    private let folders: [URL]
    /// What each app's Info.plist said, by the app's path, with the date it
    /// was changed then.
    private let cache = OSAllocatedUnfairLock<[String: (changed: Date, app: SafariWebApp?)]>(initialState: [:])

    /// The current user's Applications folder and /Applications.
    package static let applicationFolders: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications", directoryHint: .isDirectory),
        URL(filePath: "/Applications", directoryHint: .isDirectory),
    ]

    package init(folders: [URL] = SafariWebAppFinder.applicationFolders) {
        self.folders = folders
    }

    /// The web apps installed now, by name.
    package func webApps() -> [SafariWebApp] {
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
