import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

@Suite("CheckableApps")
struct CheckableAppsTests {
    /// An app bundle in `folder` with `id` and, optionally, a display name.
    private func app(_ name: String, id: String, displayName: String? = nil, in folder: URL) throws -> URL {
        var info: [String: Any] = ["CFBundleIdentifier": id, "CFBundlePackageType": "APPL"]
        if let displayName { info["CFBundleDisplayName"] = displayName }
        return try TestAppBundle.make(in: folder, name: name, info: info)
    }

    @Test("every app in the folders and one level down, by the name Finder shows, but those excluded, AutoHush and Safari web apps; links followed, hidden ones too")
    func installed() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CheckableAppsTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let deeper = folder.appending(path: "Utilities/More") // two levels down: not looked in
        try FileManager.default.createDirectory(at: deeper, withIntermediateDirectories: true)
        _ = try app("Deezer", id: "com.deezer.deezer-desktop", displayName: "Deezer Music", in: folder)
        _ = try app("Spotify", id: "com.spotify.client", in: folder)
        _ = try app("AutoHush", id: "com.autohush.AutoHush", in: folder)
        _ = try app("YouTube Music", id: "com.apple.Safari.WebApp.ABC", in: folder)
        let tv = try app("TV", id: "com.apple.TV", in: deeper)
        let link = folder.appending(path: "TV link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tv)
        #expect(lchflags(link.path, UInt32(UF_HIDDEN)) == 0) // as Safari's link into the system's cryptex
        try FileManager.default.createDirectory(at: folder.appending(path: "Not An App"), withIntermediateDirectories: true)

        let apps = CheckableApps.installedApps(in: [folder], excluding: ["com.spotify.client"])
        #expect(Set(apps.map(\.bundleID)) == ["com.deezer.deezer-desktop", "com.apple.TV"])
        // Finder's name, not the bundle's own (the user, 2026-10-20: one name everywhere).
        #expect(apps.first { $0.bundleID == "com.deezer.deezer-desktop" }?.name == "Deezer")
        #expect(apps.first { $0.bundleID == "com.apple.TV" }?.url.path == tv.resolvingSymlinksInPath().path)
    }

    /// Music, TV and Notes in the Applications folder of a scratch folder
    /// (the caller removes it), and a helper that says Music and TV can be
    /// in Now Playing, and lists TV, paused, then Music, playing.
    private func appsAndHelper() throws -> (folder: URL, applications: URL, helper: PlayerCheckHelper) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "CheckableAppsTests-\(UUID().uuidString)")
        let applications = folder.appending(path: "Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        for (name, id) in [("Music", "com.apple.Music"), ("TV", "com.apple.TV"), ("Notes", "com.apple.Notes")] {
            _ = try app(name, id: id, in: applications)
        }
        let helper = try PlayerCheckHelper.standIn(#"""
            case "$1" in
            --now-playing-reasons) shift; for app in "$@"; do case "$app" in */Music.app|*/TV.app) printf '%s\tits bundle reports\t\t\n' "$app" ;; esac; done ;;
            --now-playing-list) printf 'com.apple.TV\t300\tPaused\t0\tTV\ncom.apple.Music\t412\tPlaying\t1\tMusic\n#active\t412\n' ;;
            esac
            """#, in: folder.appending(path: "Helper"))
        return (folder, applications, helper)
    }

    @Test("the list: the apps the helper says can be in Now Playing, those in its list first, the playing one first")
    func find() async throws {
        let (folder, applications, helper) = try appsAndHelper()
        defer { try? FileManager.default.removeItem(at: folder) }
        let found = await CheckableApps.find(helper: helper, excluding: [], in: [applications])
        #expect(found.map(\.name) == ["Music", "TV"])
        #expect(found.map(\.nowPlaying) == [true, false])
    }

    @Test("the list leaves out the apps excluded")
    func findExcluding() async throws {
        let (folder, applications, helper) = try appsAndHelper()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(await CheckableApps.find(helper: helper, excluding: ["com.apple.TV"], in: [applications]).map(\.name) == ["Music"])
    }

    @Test("the list without a helper has all the apps")
    func findWithoutHelper() async throws {
        let (folder, applications, _) = try appsAndHelper()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(await CheckableApps.find(helper: nil, excluding: [], in: [applications]).map(\.name) == ["Music", "Notes", "TV"])
    }

    @Test("the list is empty when the helper fails")
    func findWhenHelperFails() async throws {
        let (folder, applications, _) = try appsAndHelper()
        defer { try? FileManager.default.removeItem(at: folder) }
        let failing = try PlayerCheckHelper.standIn("exit 1", in: folder.appending(path: "Failing"))
        #expect(await CheckableApps.find(helper: failing, excluding: [], in: [applications]).isEmpty)
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
        #expect(try AppReader.checkableApp(at: qobuz, supported: supported).get().name == "Qobuz.app Player") // as Finder shows it
        #expect(AppReader.checkableApp(at: spotify, supported: supported) == .failure(.supported("Spotify")))
        #expect(AppReader.checkableApp(at: autoHush, supported: supported) == .failure(.autoHush))
        #expect(AppReader.checkableApp(at: folder, supported: supported) == .failure(.notAnApp))
    }
}
