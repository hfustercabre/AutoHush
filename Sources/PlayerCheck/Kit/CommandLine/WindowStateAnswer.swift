import Foundation
import CheckedPlayers

// One of playercheck's one-line answers, a tab between fields: the helper
// writes it with its `line`, and AutoHush and the Player Check app read it
// with its `init?(line:)`, so neither side can drift.

/// --window-state <app>: the state its main window is in now.
package enum WindowStateAnswer: Equatable, Sendable {
    case state(CheckResult.WindowState)
    case noWindow
    case notRunning

    /// The state, when it has a window.
    package var windowState: CheckResult.WindowState? {
        if case .state(let state) = self { state } else { nil }
    }

    package var line: String {
        switch self {
        case .state(let state): state.title
        case .noWindow: "no window"
        case .notRunning: "not running"
        }
    }

    /// `nil` for anything else (`AppQuery.noApp`).
    package init?(line: some StringProtocol) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let state = CheckResult.WindowState.allCases.first(where: { $0.title == text }) {
            self = .state(state)
        } else if let answer = [WindowStateAnswer.noWindow, .notRunning].first(where: { $0.line == text }) {
            self = answer
        } else {
            return nil
        }
    }
}
