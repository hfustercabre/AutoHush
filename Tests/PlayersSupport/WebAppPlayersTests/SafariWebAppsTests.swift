import Foundation
import Testing
@testable import WebAppPlayers

@Suite("SafariWebApps")
struct SafariWebAppsTests {
    @Test("a web app is offered by the page's name, without its slogan")
    func shortName() {
        #expect(SafariWebApp.shortName("Amazon Music Unlimited | Escucha millones de canciones") == "Amazon Music Unlimited")
        #expect(SafariWebApp.shortName("YT Music") == "YT Music")
        #expect(SafariWebApp.shortName(" | Only a slogan") == " | Only a slogan")
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
        let contents = folder.appending(path: "\(file).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name, "LSTemplateApplication": true]
        try info.write(to: contents.appending(path: "Info.plist"))
    }

    @Test("the finder lists the web apps by name, and notices changes")
    func finder() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let finder = SafariWebAppFinder(folders: [folder, folder.appending(path: "missing")])
        let apps = finder.webApps()
        #expect(apps.map(\.name) == ["Amazon Music", "YT Music"])
        #expect(apps.map(\.bundleID) == [SafariWebApp.bundleIDPrefix + "B", SafariWebApp.bundleIDPrefix + "A"])
        #expect(apps.last?.url.lastPathComponent == "YT Music.app")

        try FileManager.default.removeItem(at: folder.appending(path: "YT Music.app"))
        #expect(finder.webApps().map(\.name) == ["Amazon Music"])
    }

    @Test("each web app keeps its player while it's installed")
    func players() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let players = SafariWebAppPlayers(finder: SafariWebAppFinder(folders: [folder])) {
            SafariWebAppPlayer(app: $0, page: FakeWebPage(), store: MemoryRecipeStore())
        }
        let first = players.current()
        let second = players.current()
        #expect(first.map(\.name) == ["Amazon Music", "YT Music"])
        #expect(zip(first, second).allSatisfy { $0 === $1 })
    }
}
