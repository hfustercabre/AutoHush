import CryptoKit
import Foundation
import Security

/// A release's disk image in miniature, for the `.slow` tests: AutoHush.app
/// (`/usr/bin/true` with an Info.plist), signed ad hoc as
/// com.autohush.AutoHush, needing macOS 14.4 as releases do, on a compressed
/// disk image. Each kind is made once per run, in the run's own folder and
/// with a volume named for it (hdiutil takes seconds, 16 s under the
/// parallel suite): two runs at once, as worktrees built in one VM, never
/// open the same image, which macOS refuses while the other has it open.
/// Should codesign or hdiutil fail, the tests that need one fail; the
/// others run.
struct UpdateFixture: Sendable {
    static let version = "1.2.0"
    /// A release's, which most tests share.
    static let shared = Result { try UpdateFixture.kept(.needing(macOS: "14.4")) }

    /// This run's name for its images' volumes and their folder.
    static let runID = String(UUID().uuidString.prefix(8))

    /// This run's images, removed as it ends.
    static let runFolder: URL = {
        atexit { try? FileManager.default.removeItem(at: UpdateFixture.folder(ofRun: UpdateFixture.runID)) }
        return folder(ofRun: runID)
    }()

    private static func folder(ofRun runID: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "UpdateInstallerFixture-\(runID)")
    }

    /// One of `imaged`, made once in this run: in a folder of its own, then
    /// moved where it's kept, so a test can't take one half made.
    static func kept(_ imaged: ImagedApp) throws -> UpdateFixture {
        let folder = keptFolder(for: imaged)
        if let kept = try? UpdateFixture(madeIn: folder) { return kept }
        let made = runFolder.appending(path: UUID().uuidString)
        _ = try UpdateFixture(imaged, in: made)
        do {
            try FileManager.default.moveItem(at: made, to: folder)
        } catch {
            return try UpdateFixture(madeIn: made)
        }
        return try UpdateFixture(madeIn: folder)
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
