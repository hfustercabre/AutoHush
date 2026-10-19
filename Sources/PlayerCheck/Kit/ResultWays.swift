import CheckedPlayers
import ScriptablePlayers

/// Which of the ways that worked in a check go into its setup, and in which
/// order (`CheckedPlayer`'s): only ways AutoHush can run by itself.
enum ResultWays {
    /// A way that worked: in every window state tested, or in some.
    struct Working: Sendable {
        var way: PlayerSetup.Way
        var kind: CheckResult.WayKind
        var everywhere: Bool

        init(way: PlayerSetup.Way, kind: CheckResult.WayKind, everywhere: Bool) {
            self.way = way
            self.kind = kind
            self.everywhere = everywhere
        }
    }

    /// The panel last, whatever; before it, those that worked in every state
    /// first; then AppleScript, the page, the menu.
    static func ordered(_ working: [Working]) -> [PlayerSetup.Way] {
        let rank: [CheckResult.WayKind: Int] = [.script: 0, .page: 1, .menu: 2, .panel: 3]
        return working.sorted {
            ($0.kind == .panel ? 1 : 0, $0.everywhere ? 0 : 1, rank[$0.kind]!) < ($1.kind == .panel ? 1 : 0, $1.everywhere ? 0 : 1, rank[$1.kind]!)
        }.map(\.way)
    }

    /// Whether AutoHush can run `script`: one that only toggles, with no
    /// state of its own, is sent only from the opposite state, which another
    /// sign must tell: a page or a menu among the ways kept, or what the app
    /// reports to Now Playing (`reportsReadable`). Its sound alone can't: an
    /// output stays open for seconds after a pause.
    static func canRun(_ script: ScriptSetup, besides others: [PlayerSetup.Way], reportsReadable: Bool) -> Bool {
        guard case .toggle = script.commands, script.state == nil else { return true }
        return reportsReadable || others.contains { way in
            switch way {
            case .page, .menu: true
            case .script, .panel, .mute: false
            }
        }
    }
}
