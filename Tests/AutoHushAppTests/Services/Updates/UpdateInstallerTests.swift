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
@Suite("UpdateInstaller", .serialized, .waitsTimeLimit)
struct UpdateInstallerTests {
    /// A folder of its own for each test, deleted afterwards.
    final class Scratch {
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
    final class RelaunchLog: Sendable {
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
    final class MountLog: Sendable {
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
    func installer(
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

    func release(_ version: String = Fixture.version, sha256: String? = StandIn.sha256, diskImage: Bool = true) -> AppRelease {
        .github(version, diskImage: diskImage, sha256: sha256)
    }
}

/// Whether this is macOS 27 or later, where updates open disk images with
/// `diskutil image` first.
let isMacOS27OrLater = ProcessInfo.processInfo.isOperatingSystemAtLeast(
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
enum StandIn {
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
struct Fixture: Sendable {
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
