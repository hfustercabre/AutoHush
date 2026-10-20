import AppKit
import AutoHushKit
import CheckedPlayers

/// An app Add an App… offers to check: one that can play, and that
/// AutoHush doesn't support already.
struct CheckableApp: Identifiable, Equatable, Codable, Sendable {
    let bundleID: String
    let name: String
    let url: URL
    /// In macOS's Now Playing list: whether it plays there; `nil` when it
    /// isn't listed (or the list can't be read).
    var nowPlaying: Bool?
    /// The browser that made it, when it's a Chromium browser's web app
    /// ("Google Chrome", "Brave Browser"): two of one site look alike.
    var browserName: String?

    var id: String { bundleID }

    init(bundleID: String, name: String, url: URL, nowPlaying: Bool? = nil, browserName: String? = nil) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
        self.nowPlaying = nowPlaying
        self.browserName = browserName
    }

    /// The app at `url` as Add an App names it, the same way wherever it's
    /// found (the list, Other App…): as Finder does (`AppName`); `nil` when
    /// it isn't an app with a bundle ID.
    static func at(_ url: URL) -> CheckableApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        return CheckableApp(bundleID: id, name: AppName.of(appAt: url), url: url, browserName: browserName(ofAppAt: url))
    }

    /// The name of the browser that made the app at `url`, if it's a
    /// Chromium browser's web app.
    static func browserName(ofAppAt url: URL) -> String? {
        guard let browser = CheckedAppTraits.browser(ofAppAt: url),
              let browserURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser) else { return nil }
        return AppName.of(appAt: browserURL)
    }
}
