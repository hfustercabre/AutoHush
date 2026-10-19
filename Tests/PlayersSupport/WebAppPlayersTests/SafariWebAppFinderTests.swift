import Foundation
import Testing
@testable import WebAppPlayers
import AutoHushKit
import AutoHushTestSupport
import PlayersTestSupport

@Suite("SafariWebAppFinder")
struct SafariWebAppFinderTests {
    @Test("a web app is offered by the page's name, without its slogan")
    func shortName() {
        #expect(SafariWebApp.shortName("Amazon Music Unlimited | Escucha millones de canciones") == "Amazon Music Unlimited")
        #expect(SafariWebApp.shortName("YT Music") == "YT Music")
        #expect(SafariWebApp.shortName(" | Only a slogan") == " | Only a slogan")
        #expect(SafariWebApp.shortName("Deezer - music streaming | Try Flow, download & listen to free music") == "Deezer")
        #expect(SafariWebApp.shortName("SoundCloud – Listen to free music") == "SoundCloud")
        #expect(SafariWebApp.shortName("Radio — Live") == "Radio")
        #expect(SafariWebApp.shortName("Hi-Fi Radio") == "Hi-Fi Radio") // a dash without spaces is part of the name
    }

    /// A folder of apps: web apps and others, as Safari makes them.
    private static func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "WebApps-\(UUID().uuidString)")
        try makeApp(in: folder, file: "YT Music", id: SafariWebApp.bundleIDPrefix + "A", name: "YT Music")
        try makeApp(in: folder, file: "Amazon Music | Listen", id: SafariWebApp.bundleIDPrefix + "B", name: "Amazon Music | Listen")
        try makeApp(in: folder, file: "Notes", id: "com.example.notes", name: "Notes")
        return folder
    }

    private static func makeApp(in folder: URL, file: String, id: String, name: String) throws {
        try TestAppBundle.make(in: folder, name: file, info: [
            "CFBundleIdentifier": id, "CFBundleName": name, "LSTemplateApplication": true,
            "Manifest": ["start_url": "https://\(file.lowercased().replacingOccurrences(of: " ", with: "")).example.com/"],
        ])
    }

    @Test("the finder lists the web apps by name, and notices changes; a process running one is that web app")
    func finder() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let finder = SafariWebAppFinder(folders: [folder, folder.appending(path: "missing")])
        let apps = finder.webApps()
        #expect(apps.map(\.name) == ["Amazon Music", "YT Music"])
        #expect(apps.map(\.bundleID) == [SafariWebApp.bundleIDPrefix + "B", SafariWebApp.bundleIDPrefix + "A"])
        #expect(apps.last?.url.lastPathComponent == "YT Music.app")
        #expect(apps.last?.startURL?.host() == "ytmusic.example.com")

        // Its sound is its own, not Safari's shared Web App program's; any other app's isn't a web app's.
        let amazon = folder.appending(path: "Amazon Music | Listen.app")
        #expect(SafariWebApp.source(bundleID: SafariWebApp.bundleIDPrefix + "B", at: amazon)
            == AudioSource(id: SafariWebApp.bundleIDPrefix + "B", name: "Amazon Music", bundlePath: amazon.path))
        #expect(SafariWebApp.source(bundleID: "com.example.notes", at: folder.appending(path: "Notes.app")) == nil)
        #expect(SafariWebApp.source(bundleID: SafariWebApp.bundleIDPrefix + "B", at: nil) == nil)
        #expect(SafariWebApp.source(forProcess: getpid()) == nil) // this test's own process

        try FileManager.default.removeItem(at: folder.appending(path: "YT Music.app"))
        #expect(finder.webApps(maxAge: .infinity).count == 2) // a look younger than its maximum age is reused
        #expect(finder.webApps(maxAge: 0).map(\.name) == ["Amazon Music"])
    }

    @Test("each web app keeps its player while it's installed")
    func players() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let players = SafariWebAppPlayers(finder: SafariWebAppFinder(folders: [folder])) {
            SafariWebAppPlayer(app: $0, isUntested: $1, page: FakeWebPage(), store: MemoryRecipeStore())
        }
        let first = players.current()
        let second = players.current()
        #expect(first.map(\.name) == ["Amazon Music", "YT Music"])
        #expect(zip(first, second).allSatisfy { $0 === $1 })
    }

    @Test("a suggested web app is offered until a web app opens its site, with or without www, or another of its hosts")
    func suggestions() throws {
        let app = { (start: String) in
            SafariWebApp(bundleID: SafariWebApp.bundleIDPrefix + "X", name: "X", url: URL(fileURLWithPath: "/Applications/X.app"),
                         startURL: URL(string: start))
        }
        let deezer = TestedWebApp(name: "Deezer", address: "deezer.com")
        #expect(deezer.isAdded(as: app("https://www.deezer.com/es/")))
        #expect(!deezer.isAdded(as: app("https://music.youtube.com/")))
        let amazon = TestedWebApp(name: "Amazon Music", address: "music.amazon.com", otherHosts: ["music.amazon.es"])
        #expect(amazon.isAdded(as: app("https://music.amazon.es/home")))
        #expect(!amazon.isAdded(as: app("https://www.amazon.es/")))

        #expect(amazon.covers(URL(string: "https://music.amazon.es/home")!))
        #expect(amazon.covers(URL(string: "https://www.music.amazon.com")!))
        #expect(!amazon.covers(URL(string: "https://www.amazon.es")!))
        #expect(TestedWebApp.sameSite(app("https://music.amazon.es/"), URL(string: "https://music.amazon.com")!, tested: [amazon]))
        #expect(!TestedWebApp.sameSite(app("https://music.amazon.es/"), URL(string: "https://music.amazon.com")!, tested: []))

        let suggested = [deezer, amazon, TestedWebApp(name: "YT", address: "music.youtube.com")]
        #expect(TestedWebApp.notAdded(suggested, among: [app("https://music.amazon.es/")])
            == [WebAppSuggestion(name: "Deezer", address: "deezer.com"), WebAppSuggestion(name: "YT", address: "music.youtube.com")])

        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let ytMusic = TestedWebApp(name: "YT Music", address: "ytmusic.example.com")
        let players = SafariWebAppPlayers(finder: SafariWebAppFinder(folders: [folder]), tested: [ytMusic, deezer]) {
            SafariWebAppPlayer(app: $0, isUntested: $1, page: FakeWebPage(), store: MemoryRecipeStore())
        }
        #expect(players.suggestions().map(\.name) == ["Deezer"])
        // Only YT Music's site was tested: Amazon Music's web app is untested.
        #expect(players.current().map { "\($0.name) \($0.isUntested)" } == ["Amazon Music true", "YT Music false"])
        #expect(players.current().first?.installedURL?.lastPathComponent == "Amazon Music | Listen.app")

        // A tested site's web app is named as the site, whatever Safari called it.
        let renamed = SafariWebAppPlayers(finder: SafariWebAppFinder(folders: [folder]),
                                          tested: [TestedWebApp(name: "YouTube Music", address: "ytmusic.example.com")]) {
            SafariWebAppPlayer(app: $0, isUntested: $1, page: FakeWebPage(), store: MemoryRecipeStore())
        }
        let named = renamed.current()
        #expect(named.map(\.name) == ["Amazon Music", "YouTube Music"])
        #expect(named.last?.bundleID == SafariWebApp.bundleIDPrefix + "A")
        #expect(zip(named, renamed.current()).allSatisfy { $0 === $1 }) // still kept between looks
    }
}
