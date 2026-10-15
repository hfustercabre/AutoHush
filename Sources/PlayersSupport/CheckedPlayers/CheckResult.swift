import Foundation
import WebAppPlayers

/// What a check found, as playercheck writes it for Add an App… (its
/// `--result` file): how each way to pause and play the app did in the
/// window states it was tested in, and the setup of those that worked.
package struct CheckResult: Codable, Equatable, Sendable {
    /// The ways a check tries, in its order.
    package enum WayKind: String, Codable, CaseIterable, Sendable {
        case script, menu, page, panel
    }

    /// How a way did.
    package enum Mark: String, Codable, Sendable {
        /// It paused and played the app in every window state tested.
        case works
        /// In some of them (`failedStates` lists the others).
        case some
        /// In none.
        case none
        /// The app has no such way (no dictionary, menu, page button…).
        case notThere
        /// Found, but not tried (the app didn't play).
        case notTried
        /// Not looked for (the app wasn't running, or Accessibility is missing).
        case notChecked
    }

    /// The states a player's window can be in, as the check moves it there.
    package enum WindowState: String, Codable, CaseIterable, Sendable {
        case visible, covered, otherDesktop, otherDesktopCovered, fullScreen, minimized, hidden
    }

    package struct WayResult: Codable, Equatable, Sendable {
        package var kind: WayKind
        package var mark: Mark
        /// For `.some`: the window states it didn't work in.
        package var failedStates: [WindowState]

        package init(kind: WayKind, mark: Mark, failedStates: [WindowState] = []) {
            self.kind = kind
            self.mark = mark
            self.failedStates = failedStates
        }

        /// It paused and played the app in at least one window state.
        package var worked: Bool { mark == .works || mark == .some }
    }

    /// Each way, in the check's order.
    package var ways: [WayResult]
    /// The ways that worked, ready to use; `nil` when none did.
    package var setup: PlayerSetup?
    /// Its page's Play/Pause, as the check learned it: kept as a web app's.
    package var pageButton: PlayPauseRecipe?

    package init(ways: [WayResult], setup: PlayerSetup?, pageButton: PlayPauseRecipe? = nil) {
        self.ways = ways
        self.setup = setup
        self.pageButton = pageButton
    }

    package func way(_ kind: WayKind) -> WayResult? { ways.first { $0.kind == kind } }
}
