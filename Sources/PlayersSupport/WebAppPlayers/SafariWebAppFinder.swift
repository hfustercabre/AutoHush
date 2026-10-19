import AppKit
import os
import Security
import AutoHushKit

/// A website added to the Dock from Safari (File → Add to Dock). Each is an
/// app of its own, `com.apple.Safari.WebApp.<UUID>`, usually in
/// ~/Applications, that Safari's one "Web App" program runs: a template app
/// with no program inside, only its Info.plist and icon.
package struct SafariWebApp: Equatable, Sendable {
    let bundleID: String
    /// The name it's offered under (see `shortName`).
    let name: String
    /// Where it's installed.
    let url: URL
    /// The page it opens on; `nil` when its Info.plist doesn't say.
    let startURL: URL?

    /// Every Safari web app's bundle ID starts with it.
    package static let bundleIDPrefix = "com.apple.Safari.WebApp."

    package init(bundleID: String, name: String, url: URL, startURL: URL? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.startURL = startURL
    }

    /// The web app in the bundle at `url`; `nil` for any other app.
    init?(bundleAt url: URL) {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String,
              bundleID.hasPrefix(Self.bundleIDPrefix)
        else { return nil }
        let name = (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        let startURL = ((info["Manifest"] as? [String: Any])?["start_url"] as? String).flatMap(URL.init(string:))
        self.init(bundleID: bundleID, name: Self.shortName(name), url: url, startURL: startURL)
    }

    /// Whether it opens the website at `address`: the same host, with or
    /// without "www.".
    func opens(_ address: URL) -> Bool {
        address.host().map(opens(host:)) ?? false
    }

    /// Whether it opens the website on `host`, with or without "www.".
    func opens(host: String) -> Bool {
        guard let start = startURL?.host() else { return false }
        return WebAddress.siteHost(start) == WebAddress.siteHost(host)
    }

    /// Whether the bundle at `url` is complete. Safari writes a new web app's
    /// Info.plist first, then its icon, and seals it with a code signature
    /// last, about 0.3 s later; macOS refuses to open it before ("damaged or
    /// incomplete").
    static func isSealed(at url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// A web app is named after the page's title, which often adds a slogan
    /// after " | " or a dash: "Amazon Music Unlimited | Escucha millones de
    /// canciones" is offered as "Amazon Music Unlimited", "Deezer - music
    /// streaming" as "Deezer".
    static func shortName(_ name: String) -> String {
        var short = name
        for separator in [" | ", " - ", " – ", " — "] {
            short = short.components(separatedBy: separator).first ?? short
        }
        short = short.trimmingCharacters(in: .whitespaces)
        return short.isEmpty ? name : short
    }

    /// The web app a running process is, so its sound is told apart from the
    /// other web apps' (they all run the same program); `nil` for any other
    /// process.
    package static func source(forProcess pid: pid_t) -> AudioSource? {
        let app = NSRunningApplication(processIdentifier: pid)
        return source(bundleID: app?.bundleIdentifier, at: app?.bundleURL)
    }

    /// The web app a process running as `bundleID`, from the bundle at `url`, is.
    static func source(bundleID: String?, at url: URL?) -> AudioSource? {
        guard bundleID?.hasPrefix(bundleIDPrefix) == true, let url, let webApp = SafariWebApp(bundleAt: url) else { return nil }
        return AudioSource(id: webApp.bundleID, name: webApp.name, bundlePath: url.path)
    }
}

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
