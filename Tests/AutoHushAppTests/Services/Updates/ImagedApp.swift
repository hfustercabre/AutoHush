import Foundation

/// What a test's disk image holds as AutoHush.app.
enum ImagedApp: Equatable, Sendable {
    /// The app, needing this macOS or later (releases need 14.4).
    case needing(macOS: String)
    /// A link to another app, in its place.
    case link(to: String)
}
