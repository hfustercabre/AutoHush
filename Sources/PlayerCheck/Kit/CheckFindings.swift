import Foundation
import CheckedPlayers
import WebAppPlayers

/// What a check found, made into what it writes for AutoHush (--result):
/// each way's mark, and the setup of those that worked and AutoHush can run
/// by itself (`ResultWays`), in `CheckedPlayer`'s order.
package struct CheckFindings: Sendable {
    /// What the check found of one way.
    package struct Way: Sendable {
        /// Whether the app has it: AppleScript with commands to try, a
        /// playback menu, a page's Play/Pause, a row in Now Playing.
        package var isThere: Bool
        /// Its mark when it couldn't be looked for (saying why), unless it
        /// was tried after all.
        package var notChecked: CheckResult.Mark?
        /// How it did in each window state tested; none when there were none.
        package var trials: [(state: CheckResult.WindowState, result: TrialResult)]
        /// How it did in the first window state (visible), or in its only run.
        package var first: TrialResult?
        /// How AutoHush runs it, when it works.
        package var setup: PlayerSetup.Way?

        package init(isThere: Bool, notChecked: CheckResult.Mark? = nil, trials: [(state: CheckResult.WindowState, result: TrialResult)] = [],
                     first: TrialResult? = nil, setup: PlayerSetup.Way? = nil) {
            self.isThere = isThere
            self.notChecked = notChecked
            self.trials = trials
            self.first = first
            self.setup = setup
        }

        /// Its mark over the window states it was tested in (its only run
        /// when there were none), and the states it failed in when it
        /// worked in some.
        package var mark: (mark: CheckResult.Mark, failed: [CheckResult.WindowState]) {
            if !trials.isEmpty {
                let failed = trials.filter { $0.result != .worked }.map(\.state)
                return (failed.isEmpty ? .works : failed.count == trials.count ? .none : .some, failed)
            }
            guard let first else { return (.notTried, []) }
            return (first == .worked ? .works : .none, [])
        }
    }

    package var bundleID: String
    package var appName: String
    package var appURL: URL
    package var ways: [CheckResult.WayKind: Way]
    /// Now Playing's item never seen in the menu bar, and found missing
    /// there: hidden by the user, which they can change.
    package var nowPlayingHidden = false
    /// What the app reports to Now Playing can be read (it can be the Now
    /// Playing app, and this is an administrator).
    package var reportsReadable = false
    /// The notification that announced its pauses and plays.
    package var stateNotification: String?
    package var needsLaunchOption = false
    /// Its row in Now Playing didn't follow it (`PanelRows.staleRow`).
    package var panelRowIsStale = false
    /// Where its song showed besides its windows' titles, which told its
    /// row in Now Playing too.
    package var panelClues: PanelClues?
    /// Its page's Play/Pause, as learned, when it has one.
    package var pageButton: PlayPauseRecipe?

    package init(bundleID: String, appName: String, appURL: URL, ways: [CheckResult.WayKind: Way]) {
        self.bundleID = bundleID
        self.appName = appName
        self.appURL = appURL
        self.ways = ways
    }

    /// The result; `toggleLeftOut` when AppleScript worked but only toggles,
    /// with no state and nothing else to tell AutoHush when to send it: it's
    /// marked `.toggleOnly` and not kept.
    package func result() -> (result: CheckResult, toggleLeftOut: Bool) {
        var marks: [CheckResult.WayResult] = []
        var working: [ResultWays.Working] = []
        for kind in CheckResult.WayKind.allCases {
            let way = ways[kind] ?? Way(isThere: false)
            guard way.isThere, way.notChecked == nil || way.first != nil else {
                marks.append(CheckResult.WayResult(kind: kind, mark: way.notChecked ?? .notThere))
                continue
            }
            let (mark, failed) = way.mark
            let result = CheckResult.WayResult(kind: kind, mark: mark, failedStates: mark == .some ? failed : [])
            marks.append(result)
            if result.worked, let setup = way.setup { working.append(ResultWays.Working(way: setup, kind: kind, everywhere: mark == .works)) }
        }
        if nowPlayingHidden, let index = marks.firstIndex(where: { $0.kind == .panel }), marks[index].mark == .none {
            marks[index] = CheckResult.WayResult(kind: .panel, mark: .menuBarHidden)
        }
        var toggleLeftOut = false
        if let index = working.firstIndex(where: { $0.kind == .script }), case .script(let script) = working[index].way,
           !ResultWays.canRun(script, besides: working.map(\.way), reportsReadable: reportsReadable) {
            working.remove(at: index)
            if let marked = marks.firstIndex(where: { $0.kind == .script }) { marks[marked] = CheckResult.WayResult(kind: .script, mark: .toggleOnly) }
            toggleLeftOut = true
        }
        let ordered = ResultWays.ordered(working)
        let panel = ordered.contains(where: \.isPanel)
        let setup = ordered.isEmpty ? nil
            : PlayerSetup(bundleID: bundleID, name: appName, appURL: appURL, ways: ordered, stateNotification: stateNotification,
                          needsLaunchOption: needsLaunchOption, panelRowIsStale: panelRowIsStale && panel ? true : nil,
                          panelClues: panel ? panelClues : nil)
        return (CheckResult(ways: marks, setup: setup, pageButton: pageButton), toggleLeftOut)
    }
}
