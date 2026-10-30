import Foundation
import Testing
@testable import AutoHushApp
import AutoHushTestSupport

/// The real installer against a real disk image: a tiny AutoHush.app, signed
/// ad hoc, standing in for a release. Its designated requirement plays the
/// running app's. One test at a time: the slow ones open the same disk image
/// (`UpdateFixture.shared`), which macOS won't attach again while it's attached
/// (hdiutil: “Resource busy”, 2026-10-19). Another run's are its own
/// (`UpdateFixture.runFolder`).
@Suite("UpdateInstaller", .serialized, .waitsTimeLimit)
struct UpdateInstallerTests {
    /// A folder of its own for each test, deleted afterwards.
    final class Scratch {
        private let temporary = TemporaryFolder("UpdateInstallerTests", create: false)
        var folder: URL { temporary.url }
        /// The installed app the update replaces.
        var installedApp: URL { folder.appending(path: "Applications/AutoHush.app") }
        /// What a test that opens no disk image downloads (`UpdateStandIn`).
        var download: URL { folder.appending(path: "download.dmg") }
        /// Where the installer opened disk images.
        let mounts = MountLog()
        /// What the installer moved to the Trash, in order.
        let trashed = Locked<[URL]>([])

        init() throws {
            try FileManager.default.createDirectory(at: installedApp, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: installedApp.appending(path: "version.txt"))
            try UpdateStandIn.contents.write(to: download)
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
        requirement: String? = UpdateStandIn.requirement,
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

    func release(_ version: String = UpdateFixture.version, sha256: String? = UpdateStandIn.sha256, diskImage: Bool = true) -> AppRelease {
        .github(version, diskImage: diskImage, sha256: sha256)
    }
}

/// Whether this is macOS 27 or later, where updates open disk images with
/// `diskutil image` first.
let isMacOS27OrLater = ProcessInfo.processInfo.isOperatingSystemAtLeast(
    OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
)
