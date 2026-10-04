import CryptoKit
import Foundation
import Security

/// Why this copy of AutoHush can't install updates by itself.
enum UpdateInstallUnavailability: Equatable, Sendable {
    /// It isn't signed with a certificate (a development build), so there is
    /// no way to tell that an update comes from the same developer.
    case notSignedWithCertificate
    /// It can't replace itself: the app or its folder is read-only for this
    /// user (on the disk image, or in another user's folder).
    case readOnlyLocation

    /// Shown in Settings under "Install updates automatically".
    var explanation: String {
        switch self {
        case .notSignedWithCertificate:
            return String(localized: "This copy of AutoHush can't update itself, because it isn't signed with AutoHush's certificate.",
                          comment: "Settings, under Install updates automatically (development builds)")
        case .readOnlyLocation:
            return String(localized: "AutoHush can't update itself, because it can't write to the folder it's in.",
                          comment: "Settings, under Install updates automatically")
        }
    }
}

/// Why an update could not be installed.
enum UpdateInstallError: LocalizedError, Equatable {
    case unavailable(UpdateInstallUnavailability)
    /// The release has no disk image to install from.
    case noDiskImage
    case badResponse(Int)
    /// The download doesn't match GitHub's checksum, can't be opened, or
    /// holds no AutoHush.app.
    case damaged
    /// The app in the download isn't signed with the running app's certificate.
    case notGenuine
    /// The app in the download isn't the version the release announced.
    case wrongVersion
    /// Swapping in the new app failed, for the reason given.
    case notReplaced(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            return reason.explanation
        case .noDiskImage:
            return String(localized: "This release has no disk image to install from.", comment: "Update install error")
        case .badResponse(let status):
            return String(localized: "GitHub answered with HTTP status \(status).",
                          comment: "Update check error; %lld is an HTTP status code")
        case .damaged:
            return String(localized: "The download is damaged.", comment: "Update install error")
        case .notGenuine:
            return String(localized: "The download isn't signed with the same certificate as AutoHush, so it wasn't installed.",
                          comment: "Update install error")
        case .wrongVersion:
            return String(localized: "The download doesn't contain the version GitHub announced.", comment: "Update install error")
        case .notReplaced(let reason):
            return String(localized: "AutoHush couldn't replace itself: \(reason)",
                          comment: "Update install error; %@ is the reason macOS gave")
        }
    }
}

/// An update downloaded, checked and ready to take the running app's place.
struct PreparedUpdate: Equatable, Sendable {
    let version: AppVersion
    /// The checked AutoHush.app, on the same volume as the installed one.
    let app: URL
    /// The private folder holding it; removed once installed or discarded.
    let folder: URL
}

/// A release's disk image downloaded earlier and kept, with the SHA-256 it
/// had then.
struct KeptImage: Equatable, Sendable {
    let file: URL
    let sha256: String
}

/// Installs updates. `UpdateInstaller` is the real one; tests stand in for it.
protocol UpdateInstalling: Sendable {
    /// Why this copy can't update itself, or nil when it can.
    var unavailability: UpdateInstallUnavailability? { get }
    /// Downloads `release`'s disk image to `file`, checked against the
    /// SHA-256 GitHub lists for it, and returns the file's SHA-256. Without
    /// `allowsConstrainedNetwork`, it doesn't download while Low Data Mode is on.
    func download(_ release: AppRelease, to file: URL, allowsConstrainedNetwork: Bool) async throws -> String
    /// Gets `release` ready to install and checks it: from `image`, an
    /// earlier download, when given, otherwise downloaded now (see `download`
    /// for `allowsConstrainedNetwork`).
    func prepare(_ release: AppRelease, image: KeptImage?, allowsConstrainedNetwork: Bool) async throws -> PreparedUpdate
    /// Puts `update` in the running app's place, to be opened once AutoHush quits.
    func install(_ update: PreparedUpdate) throws
    /// Deletes a prepared update that won't be installed.
    func discard(_ update: PreparedUpdate)
}

/// Replaces AutoHush with a newer release:
///
/// 1. downloads the release's disk image from GitHub, and compares it with
///    the SHA-256 GitHub lists for it (or takes an image downloaded earlier,
///    after checking it's unchanged);
/// 2. copies AutoHush.app out of it, onto the installed app's volume;
/// 3. accepts that copy only when its signature is intact and satisfies the
///    running app's designated requirement, which names AutoHush's
///    certificate, and when it is the release's version. This is the test
///    macOS uses to keep AutoHush's permissions, and nothing but AutoHush
///    signed with its certificate passes it;
/// 4. swaps it in for the running app, and has it opened as soon as this one
///    quits.
///
/// AutoHush isn't notarized, so Gatekeeper would refuse to open a copy marked
/// as downloaded. The signature check takes Gatekeeper's place: once a copy
/// passes it, its quarantine mark is removed, as the Homebrew cask does.
struct UpdateInstaller: UpdateInstalling {
    typealias Download = @Sendable (URLRequest) async throws -> (URL, URLResponse)
    /// Opens the app at a URL once AutoHush has quit; returns a way to call that off.
    typealias Relaunch = @Sendable (URL) throws -> @Sendable () -> Void

    /// Where the running app is installed.
    let appURL: URL
    /// The designated requirement updates must satisfy: the running app's
    /// own, or nil when it isn't signed with a certificate.
    let requirement: String?
    private let fetchFile: Download
    private let relaunch: Relaunch
    /// The tools tried, in order, to open the disk image.
    private let diskImageTools: [DiskImageTool]

    init(
        appURL: URL = Bundle.main.bundleURL,
        requirement: String? = UpdateInstaller.runningAppRequirement(),
        download: @escaping Download = { try await URLSession.shared.download(for: $0) },
        relaunch: @escaping Relaunch = UpdateInstaller.openAfterExit,
        diskImageTools: [DiskImageTool] = DiskImageTool.inOrderOfPreference
    ) {
        self.appURL = appURL
        self.requirement = requirement
        self.fetchFile = download
        self.relaunch = relaunch
        self.diskImageTools = diskImageTools
    }

    var unavailability: UpdateInstallUnavailability? {
        guard requirement != nil else { return .notSignedWithCertificate }
        let files = FileManager.default
        guard files.isWritableFile(atPath: appURL.path),
              files.isWritableFile(atPath: appURL.deletingLastPathComponent().path)
        else { return .readOnlyLocation }
        return nil
    }

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
            throw UpdateInstallError.notReplaced(error.localizedDescription)
        }
        discard(update)
    }

    func discard(_ update: PreparedUpdate) {
        try? FileManager.default.removeItem(at: update.folder)
    }

    // MARK: - Steps

    /// Opens the disk image read-only and out of sight in Finder, and copies
    /// AutoHush.app out of it.
    private func copyApp(outOf imageFile: URL, into folder: URL) async throws -> URL {
        let mountPoint = folder.appending(path: "Volume", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: false)
        let tool = try await attach(imageFile, at: mountPoint)

        let copied = Result {
            let source = mountPoint.appending(path: "AutoHush.app", directoryHint: .isDirectory)
            let kind = try? source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard kind?.isDirectory == true, kind?.isSymbolicLink == false else { throw UpdateInstallError.damaged }
            let app = folder.appending(path: "AutoHush.app", directoryHint: .isDirectory)
            try FileManager.default.copyItem(at: source, to: app)
            return app
        }
        await detach(mountPoint, with: tool)
        return try copied.get()
    }

    /// Opens the disk image at `mountPoint` with the first tool that manages
    /// to, and returns that tool, to close it again. A tool this macOS lacks
    /// fails, and the next one is tried.
    private func attach(_ imageFile: URL, at mountPoint: URL) async throws -> DiskImageTool {
        for tool in diskImageTools {
            let status = try? await Self.run(tool.path, tool.attachArguments(imageFile.path, Self.resolvedPath(mountPoint)))
            if status == 0 { return tool }
        }
        throw UpdateInstallError.damaged
    }

    /// Closes the disk image opened at `mountPoint` with `tool`.
    private func detach(_ mountPoint: URL, with tool: DiskImageTool) async {
        _ = try? await Self.run(tool.path, tool.detachArguments(Self.resolvedPath(mountPoint)))
    }

    /// Accepts `app` only when it's signed like the running app, intact (every
    /// file, every architecture and any nested code), and is `version`. The
    /// version is read after the signature check, which covers Info.plist.
    private func check(_ app: URL, isVersion version: AppVersion) throws {
        guard let requirement, Self.isSigned(app, satisfying: requirement) else { throw UpdateInstallError.notGenuine }
        let info = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        guard let found = (info?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init), found == version
        else { throw UpdateInstallError.wrongVersion }
    }

    // MARK: - System

    /// The hex SHA-256 of `file`, or nil when it can't be read.
    static func sha256(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isSigned(_ app: URL, satisfying requirementText: String) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// The running app's designated requirement, such as `identifier
    /// "com.autohush.AutoHush" and certificate leaf = H"085e…"`, or nil when
    /// it isn't signed with a certificate (ad hoc or not at all).
    static func runningAppRequirement() -> String? {
        var running: SecCode?
        var code: SecStaticCode?
        var information: CFDictionary?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String] as? [SecCertificate],
              !certificates.isEmpty,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess
        else { return nil }
        return text as String?
    }

    /// Removes the "downloaded from the internet" mark from `app` and
    /// everything inside it.
    static func removeQuarantine(from app: URL) {
        let contents = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        for url in [app] + contents {
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                removexattr(path, "com.apple.quarantine", XATTR_NOFOLLOW)
            }
        }
    }

    /// Opens `app` from a small shell loop that waits for AutoHush to exit;
    /// the loop outlives AutoHush. Calling the returned closure ends the loop
    /// instead.
    static func openAfterExit(_ app: URL) throws -> @Sendable () -> Void {
        let waiter = Process()
        waiter.executableURL = URL(filePath: "/bin/sh")
        waiter.arguments = [
            "-c", #"while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 0.2; done; exec /usr/bin/open "$2""#,
            "autohush-relaunch", String(getpid()), app.path,
        ]
        try waiter.run()
        let pid = waiter.processIdentifier
        return { kill(pid, SIGTERM) }
    }

    /// `url`'s path with symbolic links resolved, the way macOS records where
    /// a volume is mounted (/var/folders/… is /private/var/folders/…).
    /// `diskutil eject` finds a volume only by that path.
    private static func resolvedPath(_ url: URL) -> String {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path, let resolved = realpath(path, nil) else { return url.path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    /// Runs a command-line tool and returns its exit status, without blocking
    /// a thread while it runs.
    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: tool)
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// A command-line tool that opens a disk image read-only at a given folder,
/// hidden from Finder, and closes it again.
struct DiskImageTool: Sendable {
    let path: String
    /// The arguments that open the image (first) at the mount point (second).
    let attachArguments: @Sendable (_ image: String, _ mountPoint: String) -> [String]
    /// The arguments that close the image opened at the mount point.
    let detachArguments: @Sendable (_ mountPoint: String) -> [String]

    /// `diskutil image`, which macOS 27 recommends. macOS 15 doesn't have it.
    static let diskutil = DiskImageTool(
        path: "/usr/sbin/diskutil",
        attachArguments: { ["image", "attach", "--readOnly", "--nobrowse", "--mountPoint", $1, $0] },
        detachArguments: { ["eject", "force", $0] }
    )

    /// hdiutil, on every macOS AutoHush supports, but deprecated for attaching
    /// and detaching since macOS 27. The image's own checksum isn't verified
    /// (seconds of work): the SHA-256 and the signature check already cover
    /// every byte that matters.
    static let hdiutil = DiskImageTool(
        path: "/usr/bin/hdiutil",
        attachArguments: { ["attach", $0, "-readonly", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", $1] },
        detachArguments: { ["detach", $0, "-force"] }
    )

    /// The newer tool first, so updates keep working once macOS removes
    /// hdiutil's attach and detach; on macOS 15 it fails at once and hdiutil
    /// takes over.
    static let inOrderOfPreference = [diskutil, hdiutil]
}
