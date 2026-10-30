import CheckedPlayers

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
