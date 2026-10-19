import Foundation

/// An update downloaded, checked and ready to take the running app's place.
struct PreparedUpdate: Equatable, Sendable {
    /// The version it holds, as its release names it; for tests (the app
    /// goes by the release's).
    let version: AppVersion
    /// The checked AutoHush.app, on the same volume as the installed one.
    let app: URL
    /// The private folder holding it; removed once installed or discarded.
    let folder: URL
}
