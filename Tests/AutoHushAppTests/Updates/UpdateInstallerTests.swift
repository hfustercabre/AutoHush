import CryptoKit
import Foundation
import Security
import Testing
@testable import AutoHushApp

/// The real installer against a real disk image: a tiny AutoHush.app, signed
/// ad hoc, standing in for a release. Its designated requirement plays the
/// running app's.
@Suite("UpdateInstaller", .serialized)
struct UpdateInstallerTests {
    /// A folder of its own for each test, deleted afterwards.
    private final class Scratch {
        let folder = FileManager.default.temporaryDirectory.appending(path: "UpdateInstallerTests-\(UUID().uuidString)")
        /// The installed app the update replaces.
        var installedApp: URL { folder.appending(path: "Applications/AutoHush.app") }

        init() throws {
            try FileManager.default.createDirectory(at: installedApp, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: installedApp.appending(path: "version.txt"))
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    /// The download requests made.
    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _all: [URLRequest] = []
        var all: [URLRequest] { lock.withLock { _all } }
        func record(_ request: URLRequest) { lock.withLock { _all.append(request) } }
    }

    /// Counts relaunches and their cancellations.
    private final class RelaunchLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _opened: [URL] = []
        private var _cancelled = 0
        var opened: [URL] { lock.withLock { _opened } }
        var cancelled: Int { lock.withLock { _cancelled } }

        func relaunch(_ app: URL) -> @Sendable () -> Void {
            lock.withLock { _opened.append(app) }
            return { self.lock.withLock { self._cancelled += 1 } }
        }
    }

    private func installer(
        _ scratch: Scratch,
        requirement: String? = Fixture.shared.requirement,
        status: Int = 200,
        serving file: URL = Fixture.shared.diskImage,
        relaunchLog: RelaunchLog = RelaunchLog(),
        requests: RequestLog = RequestLog(),
        diskImageTools: [DiskImageTool] = DiskImageTool.inOrderOfPreference
    ) -> UpdateInstaller {
        UpdateInstaller(
            appURL: scratch.installedApp,
            requirement: requirement,
            download: { request in
                requests.record(request)
                // Like URLSession: a fresh temporary file the caller moves away.
                let copy = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID().uuidString)")
                try FileManager.default.copyItem(at: file, to: copy)
                return (copy, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            },
            relaunch: relaunchLog.relaunch,
            diskImageTools: diskImageTools
        )
    }

    private func release(_ version: String = Fixture.version, sha256: String? = Fixture.shared.sha256, diskImage: Bool = true) -> AppRelease {
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

    @Test("a genuine update is copied out of its disk image, next to the installed app")
    func preparesGenuineUpdate() async throws {
        try await expectPrepared(openingWith: DiskImageTool.inOrderOfPreference)
    }

    @Test("diskutil opens and closes the disk image, where macOS has `diskutil image`",
          .enabled(if: hasDiskutilImage))
    func opensWithDiskutil() async throws {
        try await expectPrepared(openingWith: [.diskutil])
    }

    @Test("hdiutil opens and closes the disk image, as on macOS 15")
    func opensWithHdiutil() async throws {
        try await expectPrepared(openingWith: [.hdiutil])
    }

    @Test("a tool that's missing or fails makes way for the next one")
    func fallsBackToNextTool() async throws {
        let missing = DiskImageTool(path: "/nonexistent/diskutil", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        let failing = DiskImageTool(path: "/usr/bin/false", attachArguments: { _, _ in [] }, detachArguments: { _ in [] })
        try await expectPrepared(openingWith: [missing, failing, .hdiutil])
    }

    /// Prepares the fixture's update, opening its disk image with `tools`,
    /// and checks the result.
    private func expectPrepared(openingWith tools: [DiskImageTool]) async throws {
        let scratch = try Scratch()
        let update = try await installer(scratch, diskImageTools: tools).prepare(release(), image: nil, allowsConstrainedNetwork: true)

        #expect(update.version == AppVersion(Fixture.version))
        let info = NSDictionary(contentsOf: update.app.appending(path: "Contents/Info.plist"))
        #expect(info?["CFBundleShortVersionString"] as? String == Fixture.version)
        #expect(UpdateInstaller.isSigned(update.app, satisfying: Fixture.shared.requirement))
        // Only the app is left: the download is deleted and the image detached.
        let contents = try FileManager.default.contentsOfDirectory(atPath: update.folder.path)
        #expect(contents.sorted() == ["AutoHush.app", "Volume"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: update.folder.appending(path: "Volume").path).isEmpty)
        #expect(Self.attachedImages().isEmpty)

        installer(scratch).discard(update)
        #expect(!FileManager.default.fileExists(atPath: update.folder.path))
    }

    @Test("an app signed by anyone else is refused")
    func refusesOtherSigners() async throws {
        let scratch = try Scratch()
        let autoHush = #"identifier "com.autohush.AutoHush" and certificate leaf = H"085edf2752c4f31bcdff25dbe14636958d50cdf6""#
        await #expect(throws: UpdateInstallError.notGenuine) {
            try await installer(scratch, requirement: autoHush).prepare(release(), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(Self.attachedImages().isEmpty)
    }

    @Test("a download that doesn't match GitHub's checksum is refused")
    func refusesWrongChecksum() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(sha256: String(repeating: "0", count: 64)), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a download that isn't a disk image is refused")
    func refusesNonImage() async throws {
        let scratch = try Scratch()
        let page = scratch.folder.appending(path: "page.html")
        try Data("<html>Not Found</html>".utf8).write(to: page)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch, serving: page).prepare(release(sha256: nil), image: nil, allowsConstrainedNetwork: true)
        }
    }

    @Test("a disk image holding another version than announced is refused")
    func refusesOtherVersion() async throws {
        let scratch = try Scratch()
        await #expect(throws: UpdateInstallError.wrongVersion) {
            try await installer(scratch).prepare(release("9.9.9"), image: nil, allowsConstrainedNetwork: true)
        }
        #expect(Self.attachedImages().isEmpty)
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
        #expect(digest == Fixture.shared.sha256)
        #expect(UpdateInstaller.sha256(of: file) == Fixture.shared.sha256)
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
        let requests = RequestLog()
        _ = try await installer(scratch, requests: requests)
            .download(release(), to: scratch.folder.appending(path: "AutoHush.dmg"), allowsConstrainedNetwork: allowed)
        #expect(requests.all.map(\.allowsConstrainedNetworkAccess) == [allowed])
    }

    @Test("an update is prepared from a kept image without downloading, and the image stays")
    func preparesFromKeptImage() async throws {
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try FileManager.default.copyItem(at: Fixture.shared.diskImage, to: kept)
        let requests = RequestLog()
        let sut = installer(scratch, requests: requests)

        let update = try await sut.prepare(release(), image: KeptImage(file: kept, sha256: Fixture.shared.sha256),
                                         allowsConstrainedNetwork: true)

        #expect(UpdateInstaller.isSigned(update.app, satisfying: Fixture.shared.requirement))
        #expect(requests.all.isEmpty)
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(Self.attachedImages().isEmpty)
        sut.discard(update)
    }

    @Test("a kept image that changed since it was downloaded is refused")
    func refusesChangedKeptImage() async throws {
        let scratch = try Scratch()
        let kept = scratch.folder.appending(path: "AutoHush-1.2.0.dmg")
        try Data("not the download".utf8).write(to: kept)
        await #expect(throws: UpdateInstallError.damaged) {
            try await installer(scratch).prepare(release(), image: KeptImage(file: kept, sha256: Fixture.shared.sha256),
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

    @Test("a failed swap leaves the installed app alone and calls the relaunch off")
    func failedSwap() throws {
        let scratch = try Scratch()
        let update = try Self.preparedUpdate(next: scratch.installedApp)
        try FileManager.default.removeItem(at: update.app) // nothing to swap in
        let log = RelaunchLog()

        #expect {
            try installer(scratch, relaunchLog: log).install(update)
        } throws: { error in
            guard case .notReplaced = error as? UpdateInstallError else { return false }
            return true
        }
        #expect(try String(contentsOf: scratch.installedApp.appending(path: "version.txt"), encoding: .utf8) == "old")
        #expect(log.cancelled == 1)
        installer(scratch).discard(update)
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

    /// Where the update disk images this test process opened are still
    /// mounted: in its own staging folders, which macOS names after it.
    private static func attachedImages() -> [String] {
        var mounts: UnsafeMutablePointer<statfs>?
        let count = Int(getmntinfo(&mounts, MNT_NOWAIT))
        let staging = "/TemporaryItems/NSIRD_\(ProcessInfo.processInfo.processName)_"
        return (0..<count).compactMap { index in
            let path = withUnsafeBytes(of: mounts![index].f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return path.contains(staging) ? path : nil
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

/// Whether this macOS has `diskutil image` (macOS 15 doesn't).
private let hasDiskutilImage: Bool = {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/sbin/diskutil")
    process.arguments = ["image", "attach", "--help"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}()

/// A release's disk image in miniature, made once per test run: AutoHush.app
/// (`/usr/bin/true` with an Info.plist), signed ad hoc as
/// com.autohush.AutoHush, on a compressed disk image.
private struct Fixture: Sendable {
    static let version = "1.2.0"
    static let shared = try! Fixture()

    let diskImage: URL
    let sha256: String
    /// The app's designated requirement (its code hash, as it's signed ad hoc).
    let requirement: String

    private init() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "UpdateInstallerFixture-\(UUID().uuidString)")
        let app = folder.appending(path: "Image/AutoHush.app")
        let executable = app.appending(path: "Contents/MacOS/AutoHush")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: executable)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.autohush.AutoHush",
            "CFBundleExecutable": "AutoHush",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": Self.version,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))
        try Self.run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "com.autohush.AutoHush", app.path])

        diskImage = folder.appending(path: "AutoHush.dmg")
        try Self.run("/usr/bin/hdiutil", ["create", "-quiet", "-fs", "HFS+", "-format", "UDZO",
                                          "-volname", "AutoHush", "-srcfolder", folder.appending(path: "Image").path,
                                          diskImage.path])
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

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }
}
