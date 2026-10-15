import Foundation
import Testing
@testable import AutoHushApp

@Suite("CheckableApps")
struct CheckableAppsTests {
    /// An app bundle in `folder` with `id` and, optionally, a display name.
    private func app(_ name: String, id: String, displayName: String? = nil, in folder: URL) throws -> URL {
        let url = folder.appending(path: "\(name).app")
        try FileManager.default.createDirectory(at: url.appending(path: "Contents"), withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        try (info as NSDictionary).write(to: url.appending(path: "Contents/Info.plist"))
        return url
    }

    @Test("every app in the folders and one level down, by its bundle's name, but those excluded, AutoHush and Safari web apps; links followed")
    func installed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CheckableAppsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let sub = folder.appending(path: "Utilities")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try app("Deezer", id: "com.deezer.deezer-desktop", displayName: "Deezer Music", in: folder)
        _ = try app("Spotify", id: "com.spotify.client", in: folder)
        _ = try app("AutoHush", id: "com.autohush.AutoHush", in: folder)
        _ = try app("YouTube Music", id: "com.apple.Safari.WebApp.ABC", in: folder)
        let tv = try app("TV", id: "com.apple.TV", in: sub)
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "TV link.app"), withDestinationURL: tv)
        try FileManager.default.createDirectory(at: folder.appending(path: "Not An App"), withIntermediateDirectories: true)

        let apps = CheckableApps.installedApps(in: [folder], excluding: ["com.spotify.client"])
        #expect(Set(apps.map(\.bundleID)) == ["com.deezer.deezer-desktop", "com.apple.TV"])
        #expect(apps.first { $0.bundleID == "com.deezer.deezer-desktop" }?.name == "Deezer Music")
    }

    @Test("those in Now Playing first, the playing one first, each group by name")
    func order() {
        let url = URL(filePath: "/Applications/X.app")
        let apps = [CheckableApp(bundleID: "c", name: "Zed", url: url), CheckableApp(bundleID: "b", name: "Beta", url: url, nowPlaying: false),
                    CheckableApp(bundleID: "a", name: "Alpha", url: url), CheckableApp(bundleID: "d", name: "Delta", url: url, nowPlaying: true)]
        #expect(CheckableApps.order(apps).map(\.name) == ["Delta", "Beta", "Alpha", "Zed"])
    }

    @MainActor
    @Test("Other App…: an app is named as the list names it; not an app, AutoHush or a supported player can't be checked")
    func otherApp() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CheckableAppsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let qobuz = try app("Qobuz.app Player", id: "com.qobuz.QobuzDesktop", displayName: "Qobuz", in: folder)
        let spotify = try app("Spotify", id: "com.spotify.client", in: folder)
        let autoHush = try app("AutoHush Test", id: "com.autohush.Test", in: folder)
        let supported = [PlayerOption(bundleID: "com.spotify.client", name: "Spotify", appURL: spotify)]
        #expect(try AppDelegate.checkableApp(at: qobuz, supported: supported).get().name == "Qobuz")
        #expect(AppDelegate.checkableApp(at: spotify, supported: supported) == .failure(.supported("Spotify")))
        #expect(AppDelegate.checkableApp(at: autoHush, supported: supported) == .failure(.autoHush))
        #expect(AppDelegate.checkableApp(at: folder, supported: supported) == .failure(.notAnApp))
    }
}
