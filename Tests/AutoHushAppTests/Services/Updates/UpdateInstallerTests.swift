import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The real installer against a real disk image: a tiny AutoHush.app, signed
/// ad hoc, standing in for a release. Its designated requirement plays the
/// running app's. One test at a time: the slow ones open the same disk image
/// (`Fixture.shared`), which macOS won't attach again while it's attached
/// (hdiutil: “Resource busy”, 2026-10-19). Another run's are its own
/// (`Fixture.runFolder`).
@Suite("UpdateInstaller", .serialized)
struct UpdateInstallerTests {
    /// A folder of its own for each test, deleted afterwards.
    private final class Scratch {
        private let temporary = TemporaryFolder("UpdateInstallerTests", create: false)
        var folder: URL { temporary.url }
        /// The installed app the update replaces.
        var installedApp: URL { folder.appending(path: "Applications/AutoHush.app") }
        /// What a test that opens no disk image downloads (`StandIn`).
        var download: URL { folder.appending(path: "download.dmg") }
        /// Where the installer opened disk images.
        let mounts = MountLog()
        /// What the installer moved to the Trash, in order.
        let trashed = Locked<[URL]>([])

        init() throws {
            try FileManager.default.createDirectory(at: installedApp, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: installedApp.appending(path: "version.txt"))
            try StandIn.contents.write(to: download)
        }
    }

    /// Counts relaunches and their cancellations.
    private final class RelaunchLog: Sendable {
        private let state = Locked((opened: [URL](), cancelled: 0))
        var opened: [URL] { state.value.opened }
        var cancelled: Int { state.value.cancelled }

        func relaunch(_ app: URL) -> @Sendable () -> Void {
            state.withLock { $0.opened.append(app) }
            return { self.state.withLock { $0.cancelled += 1 } }
        }
    }

    /// Where the installer's disk image tools opened images, to check that
    /// none is left open (this test's own, whatever else runs on the Mac),
    /// and that the staging folders `prepare` makes beside the installed app
    /// are gone.
    private final class MountLog: Sendable {
        private let mountPoints = Locked<[String]>([])
        /// Each mount point a tool was given, in order.
        var noted: [String] { mountPoints.value }

        /// `tools`, each noting where it opens an image.
        func noting(_ tools: [DiskImageTool]) -> [DiskImageTool] {
            tools.map { tool in
                DiskImageTool(path: tool.path, attachArguments: { image, mountPoint in
                    self.mountPoints.append(mountPoint)
                    return tool.attachArguments(image, mountPoint)
                }, detachArguments: tool.detachArguments)
            }
        }

        /// The noted mount points where a volume is still mounted.
        var stillMounted: [String] {
            var mounts: UnsafeMutablePointer<statfs>?
            let count = Int(getmntinfo(&mounts, MNT_NOWAIT))
            let mounted = Set((0..<count).map { index in
                withUnsafeBytes(of: mounts![index].f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            })
            return noted.filter(mounted.contains)
        }

        /// Whether a tool was asked to open an image, and every staging
        /// folder, with any copy of the app in it, is gone.
        var stagingIsGone: Bool {
            let folders = Set(noted.map { URL(filePath: $0).deletingLastPathComponent().path })
            return !folders.isEmpty && folders.allSatisfy { !FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// Serving `file`, the scratch's stand-in unless given (a disk image
    /// test serves the fixture's).
    private func installer(
        _ scratch: Scratch,
        requirement: String? = StandIn.requirement,
        status: Int = 200,
        serving file: URL? = nil,
        relaunchLog: RelaunchLog = RelaunchLog(),
        requests: Locked<[URLRequest]> = Locked([]),
        diskImageTools: [DiskImageTool] = DiskImageTool.inOrderOfPreference,
        diskImageTimeout: TimeInterval = UpdateInstaller.diskImageToolTimeout
    ) -> UpdateInstaller {
        let file = file ?? scratch.download
        return UpdateInstaller(
            appURL: scratch.installedApp,
            requirement: requirement,
            download: { request in
                requests.append(request)
                // Like URLSession: a fresh temporary file the caller moves away.
                let copy = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: file, to: copy)
                return (copy, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            },
            relaunch: relaunchLog.relaunch,
            diskImageTools: scratch.mounts.noting(diskImageTools),
            diskImageTimeout: diskImageTimeout,
            trash: { [trashed = scratch.trashed] in trashed.append($0) }
        )
    }

    private func release(_ version: String = Fixture.version, sha256: String? = StandIn.sha256, diskImage: Bool = true) -> AppRelease {
        AppRelease(
            version: AppVersion(version)!,
            pageURL: URL(string: "https://github.com/hfustercabre/AutoHush/releases/tag/v\(version)")!,
            diskImage: diskImage ? AppRelease.DiskImage(
                url: URL(string: "https://github.com/hfustercabre/AutoHush/releases/download/v\(version)/AutoHush-\(version).dmg")!,
                sha256: sha256
            ) : nil
        )
    }

    // MARK: - Preparing

    @Test("diskutil opens and closes the disk image, as from macOS 27", .slow, .enabled(if: isMacOS27OrLater))
    func opensWithDiskutil() async throws {
        try await expectPrepared(openingWith: [.diskutil])
    }

    @Test("hdiutil opens and closes the disk image, as before macOS 27", .slow)
    func opensWithHdiutil() async throws {
        try await expectPrepared(openingWith: [.hdiutil])
    }

    @Test("diskutil is tried first from macOS 27, hdiutil alone before")
    func diskImageToolOrder() {
        // From macOS 27, which deprecates hdiutil's attach and detach. On 14.4, `diskutil image`
        // opened images whose files this process couldn't read, and its eject didn't know `force`.
        let order = isMacOS27OrLater ? ["/usr/sbin/diskutil", "/usr/bin/hdiutil"] : ["/usr/bin/hdiutil"]
        #expect(DiskImageTool.inOrderOfPreference.map(\.path) == order)
    }

    @Test("a disk image tool that's missing or fails makes way for the next one, also one that can't close the image", .slow)
    func fallsBackToNextTool() async throws {
        let missing = DiskImageTool(path: "/nonexistent/diskutil", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        let failing = DiskImageTool(path: "/usr/bin/false", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        // Opens it, then fails to close it, as 14.4's diskutil did.
        let leaving = DiskImageTool(path: "/usr/bin/hdiutil", attachArguments: DiskImageTool.hdiutil.attachArguments,
                                    detachArguments: { _ in ["detach", "/nonexistent"] })
        try await expectPrepared(openingWith: [missing, failing, leaving, .hdiutil])
    }

    /// Prepares the fixture's update, opening its disk image with `tools`,
    /// and checks the result.
    private func expectPrepared(openingWith tools: [DiskImageTool]) async throws {
        let fixture = try Fixture.shared.get()
        let scratch = try Scratch()
        let update = try await installer(scratch, requirement: fixture.requirement, serving: fixture.diskImage, diskImageTools: tools)
            .prepare(release(sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)

        #expect(update.version == AppVersion(Fixture.version))
        let info = NSDictionary(contentsOf: update.app.appending(path: "Contents/Info.plist"))
        #expect(info?["CFBundleShortVersionString"] as? String == Fixture.version)
        #expect(UpdateInstaller.isSigned(update.app, satisfying: fixture.requirement))
        // Only the app is left: the download is deleted and the image detached.
        let contents = try FileManager.default.contentsOfDirectory(atPath: update.folder.path)
        #expect(contents.sorted() == ["AutoHush.app", "Volume"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: update.folder.appending(path: "Volume").path).isEmpty)
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)

        installer(scratch).discard(update)
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
    }

    @Test("an app signed by anyone else is refused, and nothing is left behind", .slow)
    func refusesOtherSigners() async throws {
        let fixture = try Fixture.shared.get()
        let scratch = try Scratch()
        let autoHush = #"identifier "com.autohush.AutoHush" and certificate leaf = H"085edf2752c4f31bcdff25dbe14636958d50cdf6""#
        await #expect(throws: UpdateInstallError.notGenuine) {
            try await installer(scratch, requirement: autoHush, serving: fixture.diskImage)
                .prepare(release(sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)
        #expect(scratch.mounts.stagingIsGone)
    }

    /// Prepares an update with a disk image tool that hangs, ignoring the
    /// request to stop as one stuck in the kernel would, given 0.3 s:
    /// refused as damaged. Returns how long it took.
    private func preparedWithHungTool(_ scratch: Scratch) async -> TimeInterval {
        let hung = DiskImageTool(path: "/bin/sh", attachArguments: { _, _ in ["-c", "trap '' TERM; sleep 5"] },
                                 detachArguments: { _ in [] })
        let started = Date()
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch, diskImageTools: [hung], diskImageTimeout: 0.3)
                .prepare(release(), image: nil, allowsConstrainedNetwork: true)
        }
        return Date().timeIntervalSince(started)
    }

    @Test("a disk image tool that hangs is stopped once its time is up, and the download refused as damaged: an install never waits for good")
    func hungToolTimesOut() async throws {
        let scratch = try Scratch()
        #expect(await preparedWithHungTool(scratch) < 4) // not waited for
    }

    @Test("a disk image tool that hangs, once stopped, leaves no staging folder")
    func hungToolLeavesNothing() async throws {
        let scratch = try Scratch()
        _ = await preparedWithHungTool(scratch)
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a disk image tool has two minutes to open or close an image")
    func diskImageToolTimeout() {
        #expect(UpdateInstaller.diskImageToolTimeout == 120)
    }

    @Test("a download that doesn't match GitHub's checksum is refused")
    func refusesWrongChecksum() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(sha256: String(repeating: "0", count: 64)), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a download that isn't a disk image is refused, and its staging folder goes", .slow)
    func refusesNonImage() async throws {
        let scratch = try Scratch()
        let page = scratch.folder.appending(path: "page.html")
        try Data("<html>Not Found</html>".utf8).write(to: page)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch, serving: page).prepare(release(sha256: nil), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a disk image is refused, leaving nothing behind, when its app isn't the version announced or needs a newer macOS, or AutoHush.app is a link",
          .slow, arguments: [
            (ImagedApp.needing(macOS: "14.4"), "9.9.9", UpdateInstallError.wrongVersion),
            (.needing(macOS: "99.0"), Fixture.version, .needsNewerMacOS("99.0")),
            (.link(to: "/System/Applications/Calculator.app"), Fixture.version, .damaged),
          ])
    func refusesUnfitImage(imaged: ImagedApp, announced: String, refusal: UpdateInstallError) async throws {
        let scratch = try Scratch()
        let fixture = try Fixture.kept(imaged)
        await #expect(throws: refusal) {
            try await installer(scratch, requirement: fixture.requirement, serving: fixture.diskImage)
                .prepare(release(announced, sha256: fixture.sha256), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(!scratch.mounts.noted.isEmpty && scratch.mounts.stillMounted.isEmpty)
        #expect(scratch.mounts.stagingIsGone)
    }

    @Test("a failed download is reported with its HTTP status")
    func refusesHTTPError() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.badResponse(404)) {
            try await installer(scratch, status: 404).prepare(release(), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a release without a disk image can't be installed")
    func refusesReleaseWithoutImage() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.noDiskImage) {
            try await installer(scratch).prepare(release(diskImage: false), image: nil, allowsConstrainedNetwork: true)
        }
    }

    // MARK: - Downloading to keep

    @Test("a download is kept where asked, checked against GitHub's checksum")
    func downloadsToFile() async throws {
        let scratch = try Scratch()
        let file = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        let digest = try await installer(scratch).download(release(), to: file, allowsConstrainedNetwork: true)
        #expect(digest == StandIn.sha256)
        #expect(UpdateInstaller.sha256(of: file) == StandIn.sha256)
    }

    @Test("a download that doesn't match GitHub's checksum is deleted")
    func deletesWrongDownload() async throws {
        let scratch = try Scratch()
        let file = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).download(release(sha256: String(repeating: "0", count: 64)), to: file,
                                                  allowsConstrainedNetwork: true)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("automatic downloads wait out Low Data Mode; ones the user asks for don't", arguments: [false, true])
    func lowDataMode(allowed: Bool) async throws {
        let scratch = try Scratch()
        let requests = Locked<[URLRequest]>([]) // the download requests made
        _ = try await installer(scratch, requests: requests)
            .download(release(), to: scratch.folder.appending(path: "AutoHush.dmg"), allowsConstrainedNetwork: allowed)
        #expect(requests.value.map(\.allowsConstrainedNetworkAccess) == [allowed])
    }

    /// The fixture's update prepared from a copy of its disk image kept in
    /// the scratch folder, marked as a browser marks a download.
    private func preparedFromKeptImage() async throws
        -> (fixture: Fixture, scratch: Scratch, kept: URL, requests: Locked<[URLRequest]>, sut: UpdateInstaller, update: PreparedUpdate) {
        let fixture = try Fixture.shared.get()
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try FileManager.default.copyItem(at: fixture.diskImage, to: kept)
        let mark = "0083;00000000;Safari;" // downloaded, as a browser marks it
        #expect(setxattr(kept.path, "com.apple.quarantine", mark, mark.utf8.count, 0, XATTR_NOFOLLOW) == 0)
        let requests = Locked<[URLRequest]>([]) // the download requests made
        let sut = installer(scratch, requirement: fixture.requirement, requests: requests)
        let update = try await sut.prepare(release(sha256: fixture.sha256), image: KeptImage(file: kept, sha256: fixture.sha256),
                                           allowsConstrainedNetwork: true)
        return (fixture, scratch, kept, requests, sut, update)
    }

    @Test("an update is prepared from a kept image without downloading, and the image stays", .slow)
    func preparesFromKeptImage() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        #expect(UpdateInstaller.isSigned(bench.update.app, satisfying: bench.fixture.requirement))
        #expect(bench.requests.value.isEmpty)
        #expect(FileManager.default.fileExists(atPath: bench.kept.path))
        #expect(!bench.scratch.mounts.noted.isEmpty && bench.scratch.mounts.stillMounted.isEmpty)
    }

    @Test("an update prepared from a kept image isn't marked as downloaded", .slow)
    func keptImageCopyNotMarked() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        let files = FileManager.default.enumerator(at: bench.update.app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in [bench.update.app] + files {
            #expect(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1, "\(url.lastPathComponent)")
        }
    }

    @Test("an update prepared from a kept image, changed after signing, fails the signature check", .slow)
    func keptImageCopyChanged() async throws {
        let bench = try await preparedFromKeptImage()
        defer { bench.sut.discard(bench.update) }
        // Its Info.plist, which the signature covers, changed: no longer what was signed.
        let info = bench.update.app.appending(path: "Contents/Info.plist")
        let changed = try #require(NSMutableDictionary(contentsOf: info))
        changed["CFBundleShortVersionString"] = "9.9.9"
        try changed.write(to: info)
        #expect(!UpdateInstaller.isSigned(bench.update.app, satisfying: bench.fixture.requirement))
    }

    @Test("a kept image that changed since it was downloaded is refused")
    func refusesChangedKeptImage() async throws {
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try Data("not the download".utf8).write(to: kept)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(), image: KeptImage(file: kept, sha256: StandIn.sha256),
                                         allowsConstrainedNetwork: true)
        }
    }

    // MARK: - Where it can install

    @Test("a copy not signed with a certificate, or that can't write to its folder, can't update itself")
    func unavailability() throws {
        let scratch = try Scratch()
        #expect(installer(scratch).unavailability == nil)
        #expect(installer(scratch, requirement: nil).unavailability == .notSignedWithCertificate)

        let applications = scratch.installedApp.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
        #expect(installer(scratch).unavailability == .readOnlyLocation)
    }

    // MARK: - What went wrong

    @Test("each error says what went wrong in the user's words, and in English for the log, a failed swap's reason too",
          arguments: [
            (UpdateInstallError.unavailable(.notSignedWithCertificate),
             "This copy of AutoHush can’t update itself, because it isn’t signed with AutoHush’s certificate.",
             "This copy isn't signed with AutoHush's certificate, so it can't update itself."),
            (.unavailable(.readOnlyLocation),
             "AutoHush can’t update itself, because it can’t write to the folder it’s in.",
             "AutoHush can't write to the folder it's in, so it can't update itself."),
            (.noDiskImage, "This release has no disk image to install from.", "The release has no disk image to install from."),
            (.badResponse(404), "GitHub answered with HTTP status 404.", "GitHub answered with HTTP status 404."),
            (.damaged, "The download is damaged.", "The download is damaged."),
            (.notGenuine, "The download isn’t signed by AutoHush’s developer, so it wasn’t installed.",
             "The download isn't signed by AutoHush's developer."),
            (.wrongVersion, "The download doesn’t contain the version GitHub announced.",
             "The download doesn't contain the version GitHub announced."),
            (.notReplaced("Le disque est plein.", logReason: "The disk is full."),
             "AutoHush couldn’t replace itself: Le disque est plein.", "AutoHush couldn't replace itself: The disk is full."),
            (.needsNewerMacOS("15.0"), "This version needs macOS 15.0 or later, so it wasn’t installed.",
             "The download needs macOS 15.0 or later."),
          ])
    func errorTexts(error: UpdateInstallError, shown: String, logged: String) {
        #expect(error.errorDescription == shown)
        #expect(error.logDescription == logged)
    }

    @Test("an update is installed only on the macOS it needs or later; a minimum it can't read doesn't hold it back",
          arguments: [("14.4", (14, 4, 1), true), ("14.4", (14, 3, 9), false), ("15", (15, 0, 0), true),
                      ("15.0.1", (15, 0, 0), false), ("26.1", (27, 0, 0), true), ("soon", (14, 4, 0), true)])
    func neededMacOS(minimum: String, system: (Int, Int, Int), installs: Bool) {
        let version = OperatingSystemVersion(majorVersion: system.0, minorVersion: system.1, patchVersion: system.2)
        #expect(UpdateInstaller.isAtLeast(minimum, version) == installs)
    }

    // MARK: - Installing

    @Test("installing swaps the update in and has it opened once AutoHush quits")
    func installs() throws {
        let scratch = try Scratch()
        let update = try Self.preparedUpdate(next: scratch.installedApp)
        let log = RelaunchLog()

        try installer(scratch, relaunchLog: log).install(update)

        #expect(try String(contentsOf: scratch.installedApp.appending(path: "version.txt"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
        #expect(log.opened == [scratch.installedApp])
        #expect(log.cancelled == 0)
    }

    @Test("a failed swap leaves the installed app alone, calls the relaunch off, and moves the copy prepared to the Trash, its folder gone")
    func failedSwap() throws {
        let scratch = try Scratch()
        let update = try Self.preparedUpdate(next: scratch.installedApp)
        // The installed app's folder can't be changed: it can't be swapped.
        let applications = scratch.installedApp.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: applications.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path) }
        let log = RelaunchLog()

        #expect {
            try installer(scratch, relaunchLog: log).install(update)
        } throws: { error in
            guard case .notReplaced = error as? UpdateInstallError else { return false }
            return true
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applications.path)
        #expect(try String(contentsOf: scratch.installedApp.appending(path: "version.txt"), encoding: .utf8) == "old")
        #expect(log.cancelled == 1)
        #expect(scratch.trashed.value == [update.app])
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
    }

    @Test("the quarantine mark is removed from the app and everything in it")
    func removesQuarantine() throws {
        let scratch = try Scratch()
        let app = scratch.installedApp
        let file = app.appending(path: "version.txt")
        let mark = "0083;00000000;Safari;"
        for url in [app, file] {
            #expect(setxattr(url.path, "com.apple.quarantine", mark, mark.utf8.count, 0, XATTR_NOFOLLOW) == 0)
        }

        UpdateInstaller.removeQuarantine(from: app)

        for url in [app, file] {
            #expect(getxattr(url.path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) == -1)
        }
    }

    /// A prepared "new" app, in a folder on the same volume as `installed`.
    private static func preparedUpdate(next installed: URL) throws -> PreparedUpdate {
        let folder = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: installed, create: true
        )
        let app = folder.appending(path: "AutoHush.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: false)
        try Data("new".utf8).write(to: app.appending(path: "version.txt"))
        return PreparedUpdate(version: AppVersion("1.2.0")!, app: app, folder: folder)
    }
}

/// Whether this is macOS 27 or later, where updates open disk images with
/// `diskutil image` first.
private let isMacOS27OrLater = ProcessInfo.processInfo.isOperatingSystemAtLeast(
    OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
)

/// What a test's disk image holds as AutoHush.app.
enum ImagedApp: Equatable, Sendable {
    /// The app, needing this macOS or later (releases need 14.4).
    case needing(macOS: String)
    /// A link to another app, in its place.
    case link(to: String)
}

/// What a test that opens no disk image downloads, and the requirement it
/// gives the installer: a few bytes and a requirement no copy is checked
/// against, so that only the `.slow` tests make disk images.
private enum StandIn {
    static let contents = Data("not a disk image".utf8)
    static let sha256 = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
    static let requirement = #"identifier "com.autohush.AutoHush""#
}

/// A release's disk image in miniature, for the `.slow` tests: AutoHush.app
/// (`/usr/bin/true` with an Info.plist), signed ad hoc as
/// com.autohush.AutoHush, needing macOS 14.4 as releases do, on a compressed
/// disk image. Each kind is made once per run, in the run's own folder and
/// with a volume named for it (hdiutil takes seconds, 16 s under the
/// parallel suite): two runs at once, as worktrees built in one VM, never
/// open the same image, which macOS refuses while the other has it open.
/// Should codesign or hdiutil fail, the tests that need one fail; the
/// others run.
private struct Fixture: Sendable {
    static let version = "1.2.0"
    /// A release's, which most tests share.
    static let shared = Result { try Fixture.kept(.needing(macOS: "14.4")) }

    /// This run's name for its images' volumes and their folder.
    static let runID = String(UUID().uuidString.prefix(8))

    /// This run's images, removed as it ends.
    static let runFolder: URL = {
        atexit { try? FileManager.default.removeItem(at: Fixture.folder(ofRun: Fixture.runID)) }
        return folder(ofRun: runID)
    }()

    private static func folder(ofRun runID: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "UpdateInstallerFixture-\(runID)")
    }

    /// One of `imaged`, made once in this run: in a folder of its own, then
    /// moved where it's kept, so a test can't take one half made.
    static func kept(_ imaged: ImagedApp) throws -> Fixture {
        let folder = keptFolder(for: imaged)
        if let kept = try? Fixture(madeIn: folder) { return kept }
        let made = runFolder.appending(path: UUID().uuidString)
        _ = try Fixture(imaged, in: made)
        do {
            try FileManager.default.moveItem(at: made, to: folder)
        } catch {
            return try Fixture(madeIn: made)
        }
        return try Fixture(madeIn: folder)
    }

    /// Where one of `imaged` is kept in this run: named by it.
    private static func keptFolder(for imaged: ImagedApp) -> URL {
        let key = SHA256.hash(data: Data("\(imaged)".utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return runFolder.appending(path: "kept-\(key)")
    }

    let diskImage: URL
    let sha256: String
    /// The app's designated requirement (its code hash, as it's signed ad hoc).
    let requirement: String

    init(_ imaged: ImagedApp = .needing(macOS: "14.4"), in folder: URL = runFolder.appending(path: UUID().uuidString)) throws {
        try Self.make(imaged, in: folder)
        try self.init(madeIn: folder)
    }

    /// One made in `folder` before.
    init(madeIn folder: URL) throws {
        let app = folder.appending(path: "Image/AutoHush.app")
        diskImage = folder.appending(path: "AutoHush.dmg")
        sha256 = SHA256.hash(data: try Data(contentsOf: diskImage)).map { String(format: "%02x", $0) }.joined()

        var code: SecStaticCode?
        var designated: SecRequirement?
        var text: CFString?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopyDesignatedRequirement(code, [], &designated) == errSecSuccess, let designated,
              SecRequirementCopyString(designated, [], &text) == errSecSuccess, let text
        else { throw CocoaError(.featureUnsupported) }
        requirement = text as String
    }

    private static func make(_ imaged: ImagedApp, in folder: URL) throws {
        let app = folder.appending(path: "Image/AutoHush.app")
        switch imaged {
        case .needing(let minimum):
            let executable = app.appending(path: "Contents/MacOS/AutoHush")
            try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: executable)
            let info: [String: Any] = [
                "CFBundleIdentifier": "com.autohush.AutoHush",
                "CFBundleExecutable": "AutoHush",
                "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": Self.version,
                "LSMinimumSystemVersion": minimum,
            ]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appending(path: "Contents/Info.plist"))
            try run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "com.autohush.AutoHush", app.path])
        case .link(let target):
            try FileManager.default.createDirectory(at: app.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: app, withDestinationURL: URL(filePath: target))
        }

        let diskImage = folder.appending(path: "AutoHush.dmg")
        let contents = folder.appending(path: "Image").path
        if case .link = imaged {
            // No signature to keep intact: a hybrid image, made at once, not in seconds.
            try run("/usr/bin/hdiutil", ["makehybrid", "-quiet", "-hfs", "-hfs-volume-name", "AutoHush \(runID)", "-o", diskImage.path, contents])
        } else {
            try run("/usr/bin/hdiutil", ["create", "-quiet", "-fs", "HFS+", "-format", "UDZO",
                                         "-volname", "AutoHush \(runID)", "-srcfolder", contents, diskImage.path])
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}
