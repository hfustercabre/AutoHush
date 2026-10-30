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
        /// The Now Playing panel's: Now Playing hidden in the menu bar, so
        /// it couldn't be tried.
        case menuBarHidden
        /// AppleScript's: it worked, but only toggles, with no state, and
        /// nothing else tells AutoHush when to send it, so it isn't kept.
        case toggleOnly
        /// Found, but not tried (the app didn't play).
        case notTried
        /// Not looked for: Automation for the app isn't allowed (AppleScript).
        case noAutomation
        /// Not looked for: Accessibility isn't allowed.
        case noAccessibility
        /// Not looked for: its window was closed, and its page can be read
        /// only from one (2026-10-27).
        case noWindow
        /// Not looked for, for another reason (the app wasn't running or
        /// didn't play).
        case notChecked
    }

    /// The states a player's window can be in, as the check moves it there
    /// (`trip`), and its windows closed: none on screen or within reach (a
    /// menu bar player's, playing on), where nothing is moved and each way
    /// is tried once, as it is (the user, 2026-10-27). Saved by their raw
    /// values: a check saved before windows closed reads back as it was.
    package enum WindowState: String, Codable, CaseIterable, Sendable {
        case visible, covered, otherDesktop, otherDesktopCovered, fullScreen, minimized, hidden, windowsClosed
    }

    /// How one way did over the window states it was tested in: its mark,
    /// and the states it failed in when it worked in only some.
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
    /// Its windows were closed: each way was tried once, as it was, in no
    /// window state of the trip, so one that worked says so, not "in every
    /// window state" (the user, 2026-10-27). False in a check saved before.
    package var windowsClosed: Bool

    package init(ways: [WayResult], setup: PlayerSetup?, pageButton: PlayPauseRecipe? = nil, windowsClosed: Bool = false) {
        self.ways = ways
        self.setup = setup
        self.pageButton = pageButton
        self.windowsClosed = windowsClosed
    }

    private enum CodingKeys: String, CodingKey {
        case ways, setup, pageButton, windowsClosed
    }

    package init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ways = try values.decode([WayResult].self, forKey: .ways)
        setup = try values.decodeIfPresent(PlayerSetup.self, forKey: .setup)
        pageButton = try values.decodeIfPresent(PlayPauseRecipe.self, forKey: .pageButton)
        windowsClosed = try values.decodeIfPresent(Bool.self, forKey: .windowsClosed) ?? false
    }
}

extension CheckResult.WindowState {
    /// The states a check moves an app's window through, in their order (the
    /// fewest moves): all but windows closed, where it has none to move.
    package static let trip: [Self] = allCases.filter { $0 != .windowsClosed }

    /// As the check's report names it (`CheckReportLine`).
    package var title: String {
        switch self {
        case .visible: "visible"
        case .covered: "covered"
        case .otherDesktop: "on another desktop"
        case .otherDesktopCovered: "covered on another desktop"
        case .fullScreen: "full screen"
        case .minimized: "minimized"
        case .hidden: "hidden"
        case .windowsClosed: "windows closed"
        }
    }
}
