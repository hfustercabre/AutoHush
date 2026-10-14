import Foundation

/// What an update check found.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(latest: AppVersion)
    case available(AppRelease)
    /// The repository has no published release yet.
    case noReleases
}
