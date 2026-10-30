import Foundation

// MARK: - What the test covers

/// What the test covers, for the summary: its trip through the window
/// states (or why there is none) and why the page wasn't checked.
@MainActor enum TestScope {
    /// The note when the app has no window open: a reason the window states
    /// weren't tested and the page wasn't checked.
    static let noWindowOpen = "no window open"

    /// The trip through the window states, for a test of an app with a window
    /// (and the Accessibility permission to move it).
    static var windowTest: WindowTest?
    /// Why there are no window states, when there aren't.
    static var windowStatesNote: String?
    /// Its windows were closed when the test came to them (no window on screen
    /// or within reach, `windowTest` nil): each way is tried once, as it is, in
    /// that state of its own (the user, 2026-10-27).
    static var windowsClosed = false
    /// Why the page wasn't checked, for the summary.
    static var pageNotChecked: PageNotChecked?
}
