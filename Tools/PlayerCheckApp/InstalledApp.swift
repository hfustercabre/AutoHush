import AutoHushKit
import Foundation
import PlayerCheckKit

/// An app found in one of the Applications folders.
struct InstalledApp: Identifiable, Hashable {
    enum Root: CaseIterable {
        case applications, user, system
        var url: URL {
            switch self {
            case .applications: ApplicationFolders.applications
            case .user: ApplicationFolders.user
            case .system: ApplicationFolders.system
            }
        }
        var title: String {
            switch self {
            case .applications: "Applications"
            case .user: "Your Applications (web apps are here)"
            case .system: "System Applications"
            }
        }
    }

    let url: URL
    let name: String
    let bundleID: String?
    let root: Root
    /// The subfolders between its Applications folder and it, e.g. "Utilities".
    let subfolder: String?
    let isSafariWebApp: Bool
    /// What draws its interface, when that keeps it from Accessibility
    /// until a switch is on: "Electron 38.4.0", "Chromium (CEF)", "Flutter"
    /// or a Chromium browser's web app ("Google Chrome web app"), and the
    /// switches a check turns on for it ("Electron's switch, else
    /// VoiceOver's switch"), as playercheck tells them (--now-playing-reasons).
    let hiddenInterface: String?
    let switches: String?
    /// Why it can be in Now Playing, from what it's built with; nil when
    /// nothing shows it can (playercheck --now-playing-reasons).
    let nowPlayingReason: String?
    var id: String { url.path }

    /// For the check's confirmation, as playercheck does it: the switch it
    /// turns on to read the app's interface, which one it leaves on, and
    /// that it may bring the app forward a moment to have its page built.
    /// A Chromium browser's web app's browser ("Google Chrome"), from the
    /// interface playercheck names ("Google Chrome web app"); nil otherwise.
    var webAppBrowser: String? {
        guard let hiddenInterface, hiddenInterface.hasSuffix(" web app") else { return nil }
        return String(hiddenInterface.dropLast(" web app".count))
    }

    var switchNote: String? {
        guard let switches else { return nil }
        if let browser = webAppBrowser {
            return "To read its page, the check turns on \(switches), which reaches all of \(browser)'s windows and tabs, and turns"
                + " it back off after, unless VoiceOver had it on: then it's left on. Each Play or Pause by its page does the same,"
                + " about 2 seconds longer."
        }
        let page = hiddenInterface == "Flutter" ? "interface" : "page"
        return "To read its \(page), the check turns on an accessibility switch (\(switches)) and turns it back off after,"
            + " unless it may have been on already (its \(page) was readable before, or VoiceOver had it on): then it's left on."
            + " If its window is out of sight, \(name) may be brought forward a moment, to its desktop and back, for its \(page) to be built."
    }

    /// Every .app in the Applications folders and their subfolders (not
    /// inside other apps), by name. Why each can be in Now Playing comes from
    /// `tool` (playercheck), asked once for them all. Off the caller's actor,
    /// as AutoHush's `CheckableApps.find`: reading the folders blocks.
    @concurrent
    static func scan(tool: URL?) async -> [InstalledApp] {
        let found = applications()
        var told: [String: NowPlayingReasonsLine] = [:]
        if let tool, !found.isEmpty {
            let (status, output) = await Checker.runAndWait(tool, CommandLineOptions.nowPlayingReasons(found.map(\.url.path)))
            if status == CheckExitStatus.done {
                for case let line? in output.split(separator: "\n").map({ NowPlayingReasonsLine(line: $0) }) { told[line.path] = line }
            }
        }
        return found.map { app in
            let line = told[app.url.path]
            return InstalledApp(url: app.url, name: app.name, bundleID: app.bundleID, root: app.root, subfolder: app.subfolder,
                                isSafariWebApp: app.bundleID?.hasPrefix("com.apple.Safari.WebApp.") == true,
                                hiddenInterface: line?.interface, switches: line?.switches, nowPlayingReason: line?.reason)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The .app bundles in the Applications folders and their subfolders.
    private static func applications() -> [(url: URL, name: String, bundleID: String?, root: Root, subfolder: String?)] {
        var found: [(url: URL, name: String, bundleID: String?, root: Root, subfolder: String?)] = []
        for root in Root.allCases {
            let base = root.url.standardizedFileURL.path
            guard let items = FileManager.default.enumerator(at: root.url, includingPropertiesForKeys: nil,
                                                             options: [.skipsPackageDescendants, .skipsHiddenFiles])
            else { continue }
            for case let url as URL in items where url.pathExtension == "app" {
                let parent = url.deletingLastPathComponent().standardizedFileURL.path
                var subfolder: String?
                if parent.count > base.count {
                    // Each folder by the name Finder shows ("Chrome Apps", not "Chrome Apps.localized").
                    var path = base
                    subfolder = parent.dropFirst(base.count + 1).split(separator: "/").map { part in
                        path += "/" + part
                        return FileManager.default.displayName(atPath: path)
                    }.joined(separator: " › ")
                }
                let bundleID = Bundle(url: url)?.bundleIdentifier
                found.append((url, AppName.of(appAt: url), bundleID, root, subfolder))
            }
        }
        return found
    }
}
