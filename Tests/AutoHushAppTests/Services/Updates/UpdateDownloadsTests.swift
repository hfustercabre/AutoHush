import Foundation
import Testing
@testable import AutoHushApp
import AutoHushKit
import AutoHushTestSupport

/// The kept download, in a folder of its own for each test.
@Suite("UpdateDownloads")
@MainActor
struct UpdateDownloadsTests {
    @MainActor
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "UpdateDownloadsTests-\(UUID().uuidString)")
        let preferences = Preferences(store: InMemoryPreferenceStore())
        let installer = MockUpdateInstaller()
        lazy var sut = UpdateDownloads(folder: folder, preferences: preferences, installer: installer)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }

        var files: [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted() }
    }

    private func release(_ version: String) -> AppRelease {
        AppRelease(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v\(version)")!,
            diskImage: .init(url: URL(string: "https://github.com/hfustercabre/AutoHush/releases/download/v\(version)/AutoHush-\(version).dmg")!,
                             sha256: nil)
        )
    }

    @Test("a stored release is kept with its checksum, in place of an earlier one")
    func store() async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        try await scratch.sut.store(release("0.3.1"), at: scratch.now, allowsConstrainedNetwork: false)

        #expect(scratch.files == ["AutoHush-0.3.1.dmg"])
        #expect(scratch.sut.isKept(release("0.3.1")))
        #expect(!scratch.sut.isKept(release("0.3.0")))
        let image = try #require(scratch.sut.image(for: release("0.3.1")))
        #expect(image.file.lastPathComponent == "AutoHush-0.3.1.dmg")
        #expect(image.sha256 == scratch.preferences.downloadedUpdate?.sha256)
    }

    @Test("a failed download leaves nothing behind")
    func failedStore() async {
        let scratch = Scratch()
        scratch.installer.downloadError = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) {
            try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.folder.path))
        #expect(scratch.preferences.downloadedUpdate == nil)
    }

    @Test("a kept image whose contents changed isn't offered for installing")
    func changedImage() async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        try Data("changed".utf8).write(to: scratch.folder.appending(path: "AutoHush-0.3.0.dmg"))
        #expect(scratch.sut.isKept(release("0.3.0"))) // still there…
        #expect(scratch.sut.image(for: release("0.3.0")) == nil) // …but not trusted
    }

    @Test("tidying keeps a wanted, recent download of the latest newer release, and deletes anything else there")
    func tidyKeeps() async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        try Data("stray".utf8).write(to: scratch.folder.appending(path: "AutoHush-0.2.9.dmg"))

        scratch.sut.tidy(running: AppVersion("0.2.0"), latest: AppVersion("0.3.0"), keeping: true,
                         now: scratch.now.addingTimeInterval(UpdateDownloads.keepFor - 60))

        #expect(scratch.files == ["AutoHush-0.3.0.dmg"])
        #expect(scratch.preferences.downloadedUpdate != nil)
    }

    @Test("tidying deletes a download that's unwanted, not newer, superseded, withdrawn or gone", arguments: [
        ("unwanted", "0.2.0", "0.3.0", false),
        ("updated by hand", "0.3.0", "0.3.0", true),
        ("superseded", "0.2.0", "0.3.1", true),
        ("withdrawn", "0.2.0", "0.2.0", true),
    ])
    func tidyDeletes(reason: String, running: String, latest: String, keeping: Bool) async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        scratch.sut.tidy(running: AppVersion(running), latest: AppVersion(latest), keeping: keeping, now: scratch.now)
        #expect(!FileManager.default.fileExists(atPath: scratch.folder.path), "\(reason)")
        #expect(scratch.preferences.downloadedUpdate == nil, "\(reason)")
        #expect(scratch.preferences.expiredUpdateVersion == nil, "\(reason)")
    }

    @Test("tidying forgets a download whose file is gone")
    func tidyMissingFile() async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        try FileManager.default.removeItem(at: scratch.folder.appending(path: "AutoHush-0.3.0.dmg"))
        scratch.sut.tidy(running: AppVersion("0.2.0"), latest: nil, keeping: true, now: scratch.now)
        #expect(scratch.preferences.downloadedUpdate == nil)
    }

    @Test("a download older than a week, or dated in the future, expires and is remembered", arguments: [
        UpdateDownloads.keepFor + 60, -2 * 24 * 60 * 60,
    ] as [TimeInterval])
    func expiry(age: TimeInterval) async throws {
        let scratch = Scratch()
        try await scratch.sut.store(release("0.3.0"), at: scratch.now, allowsConstrainedNetwork: false)
        scratch.sut.tidy(running: AppVersion("0.2.0"), latest: AppVersion("0.3.0"), keeping: true,
                         now: scratch.now.addingTimeInterval(age))
        #expect(!FileManager.default.fileExists(atPath: scratch.folder.path))
        #expect(scratch.preferences.expiredUpdateVersion == "0.3.0")
    }

    @Test("with nothing kept, tidying empties the folder")
    func tidyStray() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.folder, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: scratch.folder.appending(path: "AutoHush-0.3.0.dmg"))
        scratch.sut.tidy(running: AppVersion("0.2.0"), latest: nil, keeping: true, now: scratch.now)
        #expect(!FileManager.default.fileExists(atPath: scratch.folder.path))
    }

    @Test("downloads are kept in AutoHush's own Caches folder")
    func defaultFolder() {
        let path = UpdateDownloads.defaultFolder.path
        #expect(path.contains("/Library/Caches/"))
        #expect(path.hasSuffix("/Updates"))
    }
}
