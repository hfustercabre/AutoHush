import Foundation
import WebAppPlayers

/// What lets an app be in Now Playing (`of`), for the check and Add an App…'s list.
package enum NowPlayingReason {
    /// Why an app can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can. An app gets in through MediaPlayer
    /// (MPNowPlayingInfoCenter and MPRemoteCommandCenter, the public way;
    /// Chromium and Electron use it too), MediaRemote (Apple's apps), AVKit's
    /// player view (a video it plays), or WebKit: the pages any app shows report
    /// through WebKit's GPU process, under the app's bundle ID (Safari's web
    /// apps; a Tauri app linking only WebKit was the
    /// active Now Playing app while it played). So: the frameworks its binaries
    /// link, those in Contents/MacOS (a player's may be a plugin there) and its own
    /// frameworks'. A Chromium browser's web app links none (its launcher loads
    /// the browser's code), yet reports as itself, apart from the browser's
    /// tabs, since Chromium 130 (Chrome's and Brave's did, with their own rows
    /// in the Now Playing panel). Add an App… and the Player Check app list the
    /// apps by it (`--now-playing-reasons`).
    package static func of(appAt url: URL, bundleID: String?) -> String? {
        if bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true { return "WebKit, as a Safari web app" }
        if case .chromiumWebApp(let browserID) = PageAccess.interface(ofAppAt: url) {
            return "Chromium, as a \(BundleNames.name(of: browserID)) web app"
        }
        if bundleID == "com.apple.Safari" || bundleID?.hasPrefix("com.apple.SafariTechnologyPreview") == true { return "WebKit" }
        var binaries: [URL] = []
        if let items = FileManager.default.enumerator(at: url.appendingPathComponent("Contents/MacOS"), includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let item as URL in items where (try? item.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                binaries.append(item)
            }
        }
        for framework in (try? FileManager.default.contentsOfDirectory(at: url.appendingPathComponent("Contents/Frameworks"),
                                                                        includingPropertiesForKeys: nil)) ?? []
        where framework.pathExtension == "framework" {
            binaries.append(framework.appendingPathComponent(framework.deletingPathExtension().lastPathComponent))
        }
        var mediaPlayerIn: String?
        var others = Set<String>()
        for binary in binaries {
            let linked = MachOFile.linkedFrameworks(binary)
            if linked.contains("MediaPlayer"), mediaPlayerIn == nil { mediaPlayerIn = binary.lastPathComponent }
            others.formUnion(linked.intersection(["MediaRemote", "AVKit", "WebKit"]))
        }
        switch mediaPlayerIn {
        case "Electron Framework"?: return "MediaPlayer, through Electron"
        case "Chromium Embedded Framework"?: return "MediaPlayer, through Chromium (CEF)"
        case let name? where name.hasSuffix(" Framework"): return "MediaPlayer, through \(name)"
        case _?: return "MediaPlayer"
        case nil: break
        }
        if others.contains("MediaRemote") { return "MediaRemote" }
        if others.contains("AVKit") { return "AVKit, for videos it plays" }
        if others.contains("WebKit") { return "WebKit, for the pages it shows" }
        return nil
    }
}
