import CheckedPlayers
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

/// Why the page wasn't checked: in words for the summary, as a mark in the
/// result file (`writeResult`).
enum PageNotChecked: Equatable {
    case notRunning, noAccessibility, noWindowOpen
    /// No page at all: no page button, rather than one unchecked.
    case noPage, noSwitch
    case didntPlay
    /// Another way is pressed (`--via`).
    case notNeeded(via: Way)

    @MainActor var text: String {
        switch self {
        case .notRunning: "it isn't running"
        case .noAccessibility: "no Accessibility permission"
        case .noWindowOpen: TestScope.noWindowOpen
        case .noPage: "no page in its windows"
        case .noSwitch: "no switch was taken"
        case .didntPlay: "it didn't play"
        case .notNeeded(let via): "not needed for --via \(via.rawValue)"
        }
    }

    /// Its mark in the result file; none for no page at all, which is no
    /// page button rather than one unchecked.
    var mark: CheckResult.Mark? {
        switch self {
        case .noPage, .noSwitch: nil
        case .noAccessibility: .noAccessibility
        case .noWindowOpen: .noWindow
        case .notRunning, .didntPlay, .notNeeded: .notChecked
        }
    }
}
