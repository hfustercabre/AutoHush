import ScriptablePlayers
import WebAppPlayers

/// A built-in player's backups (the user, 2026-11-05): its other ways that
/// worked when Player Check checked it in the test VM, with how each did in
/// each window state, kept in the catalog; the Play/Pause key, which no
/// check tests, is every player's. Pressed by its window's state, its own
/// way first (`BackedUpPlayer`).
package struct BuiltInBackups: Sendable {
    /// A way its check found.
    package enum Way: Sendable, Equatable {
        /// Its playback menu, found as any app's (`MenuPlayerProfile.found`;
        /// `name` is for the log).
        case menu(name: String)
        /// Its page's Play/Pause, learned by AutoHush itself as it pauses the
        /// player its own way (Spotify's: the user, 2026-11-05).
        case page(PageAccess)
        /// Its row in the menu bar's Now Playing panel, told by what it plays
        /// by AppleScript where it says (`ScriptedSong`).
        case panel(song: ScriptedSong?)

        var kind: CheckResult.WayKind {
            switch self {
            case .menu: .menu
            case .page: .page
            case .panel: .panel
            }
        }
    }

    /// One backup, and how it did in each window state its check tried;
    /// untested where it isn't listed.
    package struct Backup: Sendable, Equatable {
        package let way: Way
        package let states: [CheckResult.WindowState: CheckResult.StateResult.Outcome]

        package init(_ way: Way, _ states: [CheckResult.WindowState: CheckResult.StateResult.Outcome]) {
            self.way = way
            self.states = states
        }

        /// As a check's result, for `WayOrder` and its Details: worked
        /// wherever it was tried (`.works`), failed in some (`.some`), or
        /// tried nowhere (`.notTried`).
        var result: CheckResult.WayResult {
            let failed = CheckResult.WindowState.trip.filter { states[$0] == .failed }
            let mark: CheckResult.Mark = states.isEmpty ? .notTried : failed.isEmpty ? .works : .some
            return CheckResult.WayResult(kind: way.kind, mark: mark, failedStates: failed,
                                         states: CheckResult.WindowState.allCases.compactMap { state in states[state].map { .init(state: state, outcome: $0) } })
        }
    }

    /// Its own way: its AppleScript, or its menu (TIDAL's, Podcasts').
    package let own: CheckResult.WayKind
    package let backups: [Backup]

    package init(own: CheckResult.WayKind, backups: [Backup]) {
        self.own = own
        self.backups = backups
    }

    /// Worked in each state of `states`, failed in `failed`; the others untested.
    package static func worked(in states: [CheckResult.WindowState],
                               failed: [CheckResult.WindowState] = []) -> [CheckResult.WindowState: CheckResult.StateResult.Outcome] {
        Dictionary(uniqueKeysWithValues: states.map { ($0, .worked) } + failed.map { ($0, .failed) })
    }
}
