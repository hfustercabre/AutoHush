import AppKit
import AutoHushKit
import AutoHushPlayers

/// The apps Add an App… offers: those in the Applications folders that can
/// be in Now Playing (so they can play: playercheck tells by what they're
/// built with), apart from those its caller excludes (the players AutoHush
/// supports, Apple's apps that are no players) and AutoHush itself; those
/// in macOS's Now Playing list first, the playing one first.
enum CheckableApps {
    /// The apps in `folders` (tests give their own), and their folders one
    /// level down ("Chrome Apps"). Off the caller's actor: reading the
    /// folders blocks.
    @concurrent
    static func find(helper: PlayerCheckHelper?, excluding: Set<String>,
                     in folders: [URL] = ApplicationFolders.all) async -> [CheckableApp] {
        let installed = installedApps(in: folders, excluding: excluding)
        guard let helper else { return order(installed) }
        async let playing = helper.canPlay(installed.map(\.url))
        async let nowPlaying = helper.nowPlaying()
        let (canPlay, listed) = await (playing, nowPlaying)
        return order(installed.filter { canPlay.contains($0.url.path) }
            .map { app in
                var app = app
                app.nowPlaying = listed[app.bundleID]
                return app
            })
    }

    /// Those in Now Playing first (the ones playing first), each group by name.
    static func order(_ apps: [CheckableApp]) -> [CheckableApp] {
        apps.sorted { lhs, rhs in
            let rank = { (app: CheckableApp) in app.nowPlaying == true ? 0 : app.nowPlaying == false ? 1 : 2 }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Every app in `folders` (and their folders one level down), but those
    /// with a bundle ID in `excluding`, AutoHush and Safari web apps (added
    /// with Add a Web App…).
    static func installedApps(in folders: [URL], excluding: Set<String>) -> [CheckableApp] {
        let files = FileManager.default
        var found: [String: CheckableApp] = [:]
        func look(in folder: URL, depth: Int) {
            // Hidden ones too: Safari's is a link into the system's cryptex,
            // flagged hidden (the Finder shows it all the same).
            guard let items = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for listed in items where !listed.lastPathComponent.hasPrefix(".") {
                let item = listed.resolvingSymlinksInPath()
                if item.pathExtension == "app" {
                    guard let app = CheckableApp.at(item), found[app.bundleID] == nil, !excluding.contains(app.bundleID),
                          app.bundleID != Bundle.main.bundleIdentifier, !app.bundleID.hasPrefix("com.autohush."),
                          !app.bundleID.hasPrefix(SupportedPlayers.safariWebAppPrefix) else { continue }
                    found[app.bundleID] = app
                } else if depth > 0, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    look(in: item, depth: depth - 1)
                }
            }
        }
        folders.forEach { look(in: $0, depth: 1) }
        return Array(found.values)
    }
}
