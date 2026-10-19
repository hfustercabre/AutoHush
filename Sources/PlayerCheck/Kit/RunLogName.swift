import Foundation
import CheckedPlayers

/// How playercheck names each run's log (`RunLog`): its time, the app, what
/// the run did, ".log", e.g. "2026-10-18 09.41.07.250 Jukebox pause via
/// panel.log". Only those are trimmed, and only those does AutoHush's Show
/// Log open: the folder may hold others' files (Finder's .DS_Store).
package enum RunLogName {
    /// What a run does, last in its log's name: a check, one without the
    /// test, a press (by one way), a relaunch.
    static let check = "check"
    static let readOnly = "read-only"
    package static let relaunch = "relaunch"

    /// A check (`readOnly`: without the test), or a press, by `way` alone.
    package static func doing(_ action: CommandLineOptions.Action?, via way: CheckResult.WayKind?, readOnly: Bool) -> String {
        action.map { $0.rawValue + (way.map { " via \($0.rawValue)" } ?? "") } ?? (readOnly ? Self.readOnly : check)
    }

    /// Every run's `doing`.
    static let doings: Set<String> = Set([check, readOnly, relaunch] + CommandLineOptions.Action.allCases.flatMap { action in
        [doing(action, via: nil, readOnly: false)] + CheckResult.WayKind.allCases.map { doing(action, via: $0, readOnly: false) }
    })

    /// The name of a log started at `date` for `app`, doing `doing`: "/"
    /// and ":" written "-".
    package static func name(at date: Date, app: String, doing: String) -> String {
        let safe = { (text: String) in text.map { "/:".contains($0) ? "-" : String($0) }.joined() }
        return "\(time().string(from: date)) \(safe(app)) \(safe(doing)).log"
    }

    /// Whether `name` is a run's log as `name(at:app:doing:)` names it.
    package static func isRunLog(_ name: String) -> Bool {
        guard name.hasSuffix(".log"), name.count > 24 else { return false }
        let start = String(name.prefix(23)), rest = name.dropFirst(23).dropLast(4)
        guard rest.first == " ", time().date(from: start) != nil else { return false }
        return doings.contains { rest.hasSuffix(" " + $0) && rest.count > $0.count + 2 }
    }

    /// The time a run's log is named by, e.g. "2026-10-18 09.41.07.250".
    private static func time() -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd HH.mm.ss.SSS"
        return format
    }
}
