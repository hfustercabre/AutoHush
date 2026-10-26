import CheckedPlayers
import Foundation
import PlayerCheckKit

/// What playercheck said about one app, as it comes in.
struct Report {
    /// `allowing`: waiting for the Accessibility permission, before anything runs.
    enum State: Equatable { case allowing, opening, checking, finished, stopped, failed(String) }
    var state: State
    var lines: [String] = []
    var date = Date()
    /// How far the check has got, from its lines as they came (`CheckProgress`,
    /// as AutoHush follows it): while it runs.
    var progress = CheckProgress()

    /// Adds a line as it comes.
    mutating func add(_ line: String) {
        lines.append(line)
        progress.add(line)
    }

    /// The lines under a heading (a line that isn't indented), whatever its
    /// case: playercheck's headings are title case, older saved checks' not.
    func section(_ heading: CheckReportLine.Heading) -> [String] {
        guard let start = lines.firstIndex(where: { $0.caseInsensitiveCompare(heading.rawValue) == .orderedSame }) else { return [] }
        return Array(lines[(start + 1)...].prefix { $0.hasPrefix(" ") })
    }
    /// Each way's line, with the more indented lines under it (its window
    /// states) attached to it.
    var ways: [Way] {
        var found: [Way] = []
        for (index, line) in section(.ways).enumerated() {
            if let state = CheckReportLine.wayState(in: line) {
                guard !found.isEmpty else { continue }
                found[found.count - 1].states.append((state.failed, state.state.replacingOccurrences(of: "minimised", with: "minimized"), state.why))
            } else if let way = Way(id: index, line: line) {
                found.append(way)
            }
        }
        return found
    }
    /// The window state the check has the app in now, while it checks.
    var testedState: CheckProgress.WindowStep? { state == .checking ? progress.windowStep : nil }
    /// The same as "covered, 2 of 7".
    var windowState: String? { testedState.map { "\($0.state?.title ?? ""), \($0.index) of \($0.count)" } }
    /// What the check does in that window state: the way it's pressing and
    /// whether it's pausing or playing it again ("By its playback menu:
    /// playing it again"), why the state isn't tested, or the move there.
    var stateActivity: String? {
        guard testedState != nil else { return nil }
        switch progress.activity {
        case .pausing(let way)?: return "By \(AppDetail.wayName(way)): pausing it"
        case .playingAgain(let way)?: return "By \(AppDetail.wayName(way)): playing it again"
        case .untested?:
            let text = lines.last { $0.hasPrefix(CheckReportLine.notTested) }?.trimmingCharacters(in: .whitespaces) ?? ""
            return text.prefix(1).uppercased() + text.dropFirst()
        case .moving?, nil: return "Moving its window there"
        }
    }
    var verdict: String {
        section(.verdict).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
    /// What playercheck asks of whoever runs it while it waits ("start
    /// playing something in <app>; …"), in its own words: the app must play
    /// for the test. Asked until it's answered (it plays, it paused,
    /// Accessibility is decided), the wait ends ("stopped…", "it didn't…")
    /// or its section does (`CheckProgress.request`).
    var request: String? {
        guard state == .checking, progress.request != nil,
              let text = lines.lazy.reversed().compactMap({ CheckReportLine.requestText(in: $0) }).first else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }
    /// The whole report, with a blank line before each heading.
    var text: String {
        lines.enumerated().map { index, line in
            index > 0 && !line.hasPrefix(" ") ? "\n" + line : line
        }.joined(separator: "\n")
    }
}
