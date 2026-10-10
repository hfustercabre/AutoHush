import Foundation

/// What AutoHush does when its automatic check finds a newer version
/// (Settings → Updates).
package enum AutomaticUpdates: String, CaseIterable, Sendable {
    /// Lets the user know; installing is up to them.
    case notify
    /// Downloads it and lets the user know; it's installed when they say so.
    case download
    /// Installs it at a moment when AutoHush can restart unnoticed, and lets
    /// the user know afterwards.
    case install
}

/// An update downloaded and kept until it's installed, for at most a week.
package struct DownloadedUpdate: Equatable, Sendable {
    /// Its version, e.g. "0.3.8".
    package let version: String
    /// Hex SHA-256 of the disk image, checked again before installing it.
    package let sha256: String
    package let downloadedAt: Date

    package init(version: String, sha256: String, downloadedAt: Date) {
        self.version = version
        self.sha256 = sha256
        self.downloadedAt = downloadedAt
    }
}
