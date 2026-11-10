import Foundation
import AutoHushKit

/// The update kept for "Download it and notify me": at most one disk image,
/// in AutoHush's Caches folder. It's deleted once installed, replaced by a
/// newer release, unwanted, or a week old, and nothing else is ever left in
/// that folder.
@MainActor
final class UpdateDownloads {
    /// How long a download is kept unused.
    nonisolated static let keepFor: TimeInterval = 7 * 24 * 60 * 60

    /// `~/Library/Caches/<bundle identifier>/Updates`.
    static var defaultFolder: URL {
        ProjectInfo.cachesFolder.appending(path: "Updates", directoryHint: .isDirectory)
    }

    let folder: URL
    private let preferences: Preferences
    private let installer: any UpdateInstalling
    /// A file's SHA-256 in hex; `nil` when it can't be read.
    private let checksum: @Sendable (URL) -> String?

    init(folder: URL, preferences: Preferences, installer: any UpdateInstalling,
         checksum: @escaping @Sendable (URL) -> String? = UpdateInstaller.sha256(of:)) {
        self.folder = folder
        self.preferences = preferences
        self.installer = installer
        self.checksum = checksum
    }

    /// Whether `release` is kept: recorded, and its file is there. Installing
    /// checks its contents too (`image(for:)`).
    func isKept(_ release: AppRelease) -> Bool {
        preferences.downloadedUpdate.flatMap { AppVersion($0.version) } == release.version
            && FileManager.default.fileExists(atPath: file(for: release.version).path)
    }

    /// The kept disk image of `release`, when it's there and unchanged since
    /// it was downloaded. Its whole file is read for that, off the main actor.
    func image(for release: AppRelease) async -> KeptImage? {
        guard let record = preferences.downloadedUpdate, AppVersion(record.version) == release.version else { return nil }
        let file = file(for: release.version)
        guard await Self.read(file, with: checksum) == record.sha256,
              preferences.downloadedUpdate == record // not removed or replaced meanwhile
        else { return nil }
        return KeptImage(file: file, sha256: record.sha256)
    }

    @concurrent
    private nonisolated static func read(_ file: URL, with checksum: @Sendable (URL) -> String?) async -> String? {
        checksum(file)
    }

    /// Downloads `release` and keeps it, in place of any earlier download.
    func store(_ release: AppRelease, at now: Date, allowsConstrainedNetwork: Bool) async throws {
        remove()
        let file = file(for: release.version)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let sha256 = try await installer.download(release, to: file, allowsConstrainedNetwork: allowsConstrainedNetwork)
            preferences.downloadedUpdate = DownloadedUpdate(version: release.version.description, sha256: sha256, downloadedAt: now)
        } catch {
            remove()
            throw error
        }
    }

    /// Deletes the kept download and its folder.
    func remove() {
        preferences.downloadedUpdate = nil
        try? FileManager.default.removeItem(at: folder)
    }

    /// Deletes the kept download when it's no longer wanted (`keeping` is
    /// false), isn't newer than the `running` version, isn't the `latest`
    /// release (a newer one came out, or it was withdrawn), its file is gone,
    /// or it's older than `keepFor`. An expired version is remembered, so it
    /// isn't downloaded again. Anything else in the folder is deleted too.
    func tidy(running: AppVersion?, latest: AppVersion?, keeping: Bool, now: Date) {
        guard let record = preferences.downloadedUpdate, let version = AppVersion(record.version) else {
            remove()
            return
        }
        let file = file(for: version)
        let unwanted = !keeping
            || running.map { version <= $0 } == true
            || latest.map { version != $0 } == true
            || !FileManager.default.fileExists(atPath: file.path)
        // A download date in the future (the clock went back) can't be trusted.
        let age = now.timeIntervalSince(record.downloadedAt)
        let expired = age > Self.keepFor || age < -24 * 60 * 60
        if expired && !unwanted { preferences.expiredUpdateVersion = record.version }
        if unwanted || expired {
            remove()
            return
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for item in contents where item.lastPathComponent != file.lastPathComponent {
            try? FileManager.default.removeItem(at: item)
        }
    }

    private func file(for version: AppVersion) -> URL {
        folder.appending(path: "AutoHush-\(version.tagName).dmg")
    }
}
