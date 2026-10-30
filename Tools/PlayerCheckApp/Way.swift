import CheckedPlayers
import PlayerCheckKit

/// One line of playercheck's "Ways to Control It" (`CheckReportLine.way(in:)`),
/// with the window states under it (those it failed in, or that weren't tested).
struct Way: Identifiable {
    let id: Int
    /// ✓ worked in every window state tested, ⚠ in some, ✗ in none (or not
    /// there), ? found but not tried, – not checked.
    let mark: CheckReportLine.WayMark
    /// The way its title names.
    let kind: CheckResult.WayKind?
    let title: String
    let detail: String
    /// "      ✗ covered: why" → (failed, "covered", "why"); "– …: not tested (…)" → not failed.
    var states: [(failed: Bool, state: String, why: String)] = []

    /// "  ✓ AppleScript: pausing … worked" → works, "AppleScript", "pausing … worked".
    init?(id: Int, line: String) {
        guard let way = CheckReportLine.way(in: line) else { return nil }
        self.id = id
        mark = way.mark
        kind = way.way
        title = way.title
        detail = way.detail
    }

    /// Its playercheck --via, for the ways that can play and pause: AppleScript
    /// once it worked in the check, whatever its kind (`--via script` handles
    /// a play that toggles too), but before that only as the supported
    /// scriptable players have it (commands of their own kind, not tried,
    /// aren't offered); the menu, the page, the Now Playing panel.
    var via: CheckResult.WayKind? {
        kind == .script && detail.contains(CheckReportLine.unlikeScriptablePlayers) ? nil : kind
    }
    /// A way to play and pause with: it worked in the check (in every window
    /// state or some), or was found.
    var canControl: Bool { via != nil && (mark == .works || mark == .some || mark == .notTried) }

    /// Whether it worked in its check with the app's window in `state` (as
    /// `playercheck --window-state` tells it): it worked in every state
    /// tested, or some, and that one isn't listed under it as failed or not
    /// tested. On another desktop, covered there too: the window list can't
    /// tell the two apart.
    func passes(_ state: CheckResult.WindowState) -> Bool {
        guard mark == .works || mark == .some else { return false }
        let wanted = (state == .otherDesktop ? [state, .otherDesktopCovered] : [state]).map(\.title)
        return !states.contains { wanted.contains($0.state) || $0.state == CheckReportLine.allWindowStates }
    }
}

extension CheckResult.WayKind {
    /// The way as a sentence names it: "by \(inSentence)".
    var inSentence: String {
        switch self {
        case .script: "AppleScript"
        case .menu: "its playback menu"
        case .page: "its page's button"
        case .panel: "its row in the Now Playing panel"
        }
    }
}
