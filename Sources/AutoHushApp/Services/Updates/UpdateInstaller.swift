import CryptoKit
import Foundation
import AutoHushKit

/// Replaces AutoHush with a newer release:
///
/// 1. downloads the release's disk image from GitHub, and compares it with
///    the SHA-256 GitHub lists for it (or takes an image downloaded earlier,
///    after checking it's unchanged);
/// 2. copies AutoHush.app out of it, onto the installed app's volume;
/// 3. accepts that copy only when its signature is intact and satisfies the
///    running app's designated requirement, which for a release names
///    AutoHush's bundle ID and its developer team, and when it is the
///    release's version. This is the test macOS uses to keep AutoHush's
///    permissions, and nothing but AutoHush signed by its team passes it;
/// 4. swaps it in for the running app, and has it opened as soon as this one
///    quits. A copy that couldn't be swapped in goes to the Trash.
///
/// AutoHush isn't notarized, so Gatekeeper would refuse to open a copy marked
/// as downloaded. The signature check takes Gatekeeper's place: once a copy
/// passes it, its quarantine mark is removed, as the Homebrew cask does.
/// The disk image is in `+DiskImage`, the checks in `+Signature`.
struct UpdateInstaller: UpdateInstalling {
    typealias Download = @Sendable (URLRequest) async throws -> (URL, URLResponse)
    /// Opens the app at a URL once AutoHush has quit; returns a way to call that off.
    typealias Relaunch = @Sendable (URL) throws -> @Sendable () -> Void
    /// Moves a file to the Trash.
    typealias Trash = @Sendable (URL) -> Void

    /// Where the running app is installed.
    let appURL: URL
    /// The designated requirement updates must satisfy: the running app's
    /// own, or nil when it isn't signed with a certificate.
    let requirement: String?
    private let fetchFile: Download
    private let relaunch: Relaunch
    /// The tools tried, in order, to open the disk image; when the one that
    /// opened it can't close it, the others are tried.
    let diskImageTools: [DiskImageTool]
    /// How long each of them may take (`diskImageToolTimeout`).
    let diskImageTimeout: TimeInterval
    private let trash: Trash

    /// How long a disk image tool may take before it's stopped and the image
    /// taken as damaged: one that hangs (DiskArbitration stuck) would
    /// otherwise hold every install until AutoHush quits.
    static let diskImageToolTimeout: TimeInterval = 120

    init(
        appURL: URL = Bundle.main.bundleURL,
        requirement: String? = UpdateInstaller.runningAppRequirement(),
        download: @escaping Download = { try await URLSession.updates.download(for: $0) },
        relaunch: @escaping Relaunch = RelaunchWaiter.openAfterExit,
        diskImageTools: [DiskImageTool] = DiskImageTool.inOrderOfPreference,
        diskImageTimeout: TimeInterval = UpdateInstaller.diskImageToolTimeout,
        trash: @escaping Trash = { try? FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.appURL = appURL
        self.requirement = requirement
        self.fetchFile = download
        self.relaunch = relaunch
        self.diskImageTools = diskImageTools
        self.diskImageTimeout = diskImageTimeout
        self.trash = trash
    }

    var unavailability: UpdateInstallUnavailability? {
        guard requirement != nil else { return .notSignedWithCertificate }
        let files = FileManager.default
        guard files.isWritableFile(atPath: appURL.path),
              files.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
        else { return .readOnlyLocation }
        return nil
    }

    // `download` and `prepare` run off the caller's actor: hashing the disk
    // image, copying the app out of it and checking its signature block.
    @concurrent
    func download(_ release: AppRelease, to file: URL, allowsConstrainedNetwork: Bool) async throws -> String {
        guard let image = release.diskImage else { throw UpdateInstallError.noDiskImage }
        var request = URLRequest(url: image.url)
        request.timeoutInterval = 60
        request.allowsConstrainedNetworkAccess = allowsConstrainedNetwork
        let (downloaded, response) = try await fetchFile(request)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: downloaded, to: file)
        do {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateInstallError.badResponse(status) }
            guard let digest = Self.sha256(of: file), image.sha256 == nil || digest == image.sha256
            else { throw UpdateInstallError.damaged }
            return digest
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
    }

    @concurrent
    func prepare(_ release: AppRelease, image kept: KeptImage?, allowsConstrainedNetwork: Bool) async throws -> PreparedUpdate {
        if let unavailability { throw UpdateInstallError.unavailable(unavailability) }
        guard release.diskImage != nil else { throw UpdateInstallError.noDiskImage }
        // On the installed app's volume, so that swapping them is one rename.
        let folder = try FileManager.default.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true
        )
        do {
            let imageFile: URL
            if let kept {
                guard Self.sha256(of: kept.file) == kept.sha256 else { throw UpdateInstallError.damaged }
                imageFile = kept.file
            } else {
                imageFile = folder.appending(path: "AutoHush.dmg")
                _ = try await download(release, to: imageFile, allowsConstrainedNetwork: allowsConstrainedNetwork)
            }
            let app = try await copyApp(outOf: imageFile, into: folder)
            if kept == nil { try FileManager.default.removeItem(at: imageFile) }
            try check(app, isVersion: release.version)
            Self.removeQuarantine(from: app)
            return PreparedUpdate(version: release.version, app: app, folder: folder)
        } catch {
            // Never a folder removed with an image still mounted in it (one
            // that mounted after its tool gave up): the removal would fail
            // and the volume stay hidden there.
            let mountPoint = folder.appending(path: "Volume", directoryHint: .isDirectory)
            if Self.isMounted(at: Self.resolvedPath(mountPoint)) { await detach(mountPoint, openedWith: 0) }
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func install(_ update: PreparedUpdate) throws {
        let cancelRelaunch = try relaunch(appURL)
        do {
            _ = try FileManager.default.replaceItemAt(appURL, withItemAt: update.app)
        } catch {
            cancelRelaunch()
            // The next try prepares a new copy.
            if FileManager.default.fileExists(atPath: update.app.path) { trash(update.app) }
            discard(update)
            throw UpdateInstallError.notReplaced(error.localizedDescription, logReason: LogMessage.englishDescription(of: error))
        }
        discard(update)
    }

    func discard(_ update: PreparedUpdate) {
        try? FileManager.default.removeItem(at: update.folder)
    }

    // MARK: - System

    /// The hex SHA-256 of `file`, or nil when it can't be read.
    static func sha256(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
