import Foundation

/// An update downloaded, checked and ready to take the running app's place.
struct PreparedUpdate: Equatable, Sendable {
    let version: AppVersion
    /// The checked AutoHush.app, on the same volume as the installed one.
    let app: URL
    /// The private folder holding it; removed once installed or discarded.
    let folder: URL
}
