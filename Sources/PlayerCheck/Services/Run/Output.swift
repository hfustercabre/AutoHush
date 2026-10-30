import Foundation
import PlayerCheckKit

// MARK: - The report

/// Set for --play and --pause: the checks run silently, then one line says what was done.
@MainActor var quiet = action != nil

/// A line of the report: printed (unless `quiet`) and logged. No line holds
/// the home folder's path (`~` instead), nor what was playing
/// (`PrivateText`): the log may be posted in an issue.
@MainActor func say(_ line: String = "") {
    let line = PrivateText.redacted(line)
    log(line)
    guard !quiet else { return }
    print(line)
    fflush(nil)
}

/// `text` with --developer, else nothing: the report's parts that name
/// AutoHush's own types, for whoever adds a player to the code.
func forDevelopers(_ text: String) -> String { developer ? text : "" }

/// Says why it can't go on, and ends.
func fail(_ line: String) -> Never {
    let line = PrivateText.redacted(line)
    log("playercheck: \(line)")
    try? FileHandle.standardError.write(contentsOf: Data("playercheck: \(line)\n".utf8))
    exit(CheckExitStatus.failed)
}

// MARK: - The run's log

/// This run's log (`RunLog`).
let runLog = RunLog()

/// A line in the run's log only.
func log(_ line: String) { runLog.write(line) }

/// The input block's line, in the run's log only: it doesn't count as the
/// check going on (the watchdog's minute isn't restarted by it).
func logAside(_ line: String) { runLog.write(line, progress: false) }
