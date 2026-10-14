import Foundation

/// A published release: its version, its GitHub page, its notes and, when it
/// has one, the disk image AutoHush installs it from.
struct AppRelease: Equatable, Sendable {
    /// The release's `AutoHush-<version>.dmg`, as GitHub lists it.
    struct DiskImage: Equatable, Sendable {
        let url: URL
        /// Hex SHA-256 of the file, when GitHub reports one.
        let sha256: String?
    }

    let version: AppVersion
    let pageURL: URL
    let diskImage: DiskImage?
    /// What's new, in Markdown: the release's CHANGELOG section.
    let notes: String?

    init(version: AppVersion, pageURL: URL, diskImage: DiskImage? = nil, notes: String? = nil) {
        self.version = version
        self.pageURL = pageURL
        self.diskImage = diskImage
        self.notes = notes
    }
}
