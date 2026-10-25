import Observation

/// Which page Settings shows, and the pages shown before and after it, as
/// System Settings keeps them (the user, 2026-10-25: Behavior's rows open
/// Fine-Tuning): the window's title follows the page; Back and Forward
/// (the toolbar's arrows, ⌘[ and ⌘]) walk the history. Settings opened
/// afresh starts it over (`clearHistory`).
@MainActor
@Observable
final class SettingsNavigation {
    var page = SettingsWindowController.Page.general {
        didSet {
            guard page != oldValue else { return }
            if !isWalkingHistory {
                back.append(oldValue)
                forward.removeAll()
            }
            onChange?(page)
        }
    }
    /// The pages Back goes to, the last first; Forward's, the next last.
    private(set) var back: [SettingsWindowController.Page] = []
    private(set) var forward: [SettingsWindowController.Page] = []
    @ObservationIgnored var onChange: ((SettingsWindowController.Page) -> Void)?
    @ObservationIgnored private var isWalkingHistory = false

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(page)
        walk(to: previous)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(page)
        walk(to: next)
    }

    func clearHistory() {
        back.removeAll()
        forward.removeAll()
    }

    private func walk(to page: SettingsWindowController.Page) {
        isWalkingHistory = true
        defer { isWalkingHistory = false }
        self.page = page
    }
}
