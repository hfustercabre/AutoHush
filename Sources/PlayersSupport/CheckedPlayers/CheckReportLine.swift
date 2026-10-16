import Foundation

/// The lines of playercheck's report that AutoHush follows a check by (its
/// panel and its shade, `CheckProgress`): the helper writes them with these,
/// and AutoHush reads them with these, so a rewording can't leave the panel
/// behind. The rest of the report is English for whoever reads the log.
package enum CheckReportLine {
    /// The report's parts, as their headings say (at the line's start).
    package enum Heading: String, CaseIterable, Sendable {
        case scripting = "Scripting Dictionary"
        case menu = "Playback Menu"
        case sound = "Sound and Now Playing"
        case permissions = "Permissions"
        case playing = "Playing"
        case windowStates = "Window States"
        case page = "Page Buttons"
        case pressTest = "Press Test"
        case ways = "Ways to Control It"
        case verdict = "Verdict"
    }

    /// What the check asks whoever runs it to do, within some minutes.
    package enum Request: Sendable, Equatable {
        case play, pause, allowAccessibility
    }

    /// "  waiting: start playing something in Deezer; … (up to 2 minutes)":
    /// `text` starts as `request(in:)` reads it.
    package static func waiting(_ text: String, minutes: Int) -> String {
        waitingPrefix + text + " (up to \(minutes) minutes)"
    }

    /// The request a "  waiting: " line makes, and its minutes; `nil` for any other line.
    package static func request(in line: String) -> (request: Request?, minutes: Int?)? {
        guard line.hasPrefix(waitingPrefix) else { return nil }
        let text = line.dropFirst(waitingPrefix.count)
        let request: Request? = text.hasPrefix("start playing") ? .play
            : text.hasPrefix("pause ") ? .pause
            : text.hasPrefix("allow Accessibility") ? .allowAccessibility : nil
        let minutes = text.range(of: "up to ").flatMap { Int(text[$0.upperBound...].prefix { $0.isNumber }) }
        return (request, minutes)
    }

    private static let waitingPrefix = "  waiting: "

    /// Lines that answer a request: it plays, it paused, it didn't, the
    /// check stopped, Accessibility was answered.
    package static let answers = ["  it plays", "  it paused", "  it didn't", "  stopped", "  Accessibility:"]

    /// The mouse and keyboard are blocked from this line (it goes on with why).
    package static let blocked = "  your clicks, scrolling and keys are blocked"
    /// And free from this one (it may go on with why).
    package static let free = "  mouse and keyboard free again"

    /// "  State 3 of 7: on another desktop".
    package static func windowState(_ index: Int, of count: Int, _ state: CheckResult.WindowState) -> String {
        "  State \(index) of \(count): \(state.title)"
    }

    /// The window state a "  State n of m: …" line says.
    package static func windowState(in line: String) -> (index: Int, count: Int, state: CheckResult.WindowState?)? {
        guard line.hasPrefix(statePrefix), let colon = line.range(of: ": ") else { return nil }
        let numbers = line.dropFirst(statePrefix.count)[..<colon.lowerBound].components(separatedBy: " of ").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        let title = String(line[colon.upperBound...])
        return (numbers[0], numbers[1], CheckResult.WindowState.allCases.first { $0.title == title })
    }

    private static let statePrefix = "  State "

    /// A trial's label, which its line starts with (after two spaces): "by
    /// script (pause, play)", "by its menu", "by its page's button", "by its
    /// page's learned button", "by the Now Playing panel".
    package static func trial(_ way: CheckResult.WayKind, detail: String? = nil, learned: Bool = false) -> String {
        let label = switch way {
        case .script: "by script"
        case .menu: "by its menu"
        case .page: learned ? "by its page's learned button" : "by its page's button"
        case .panel: "by the Now Playing panel"
        }
        return detail.map { "\(label) (\($0))" } ?? label
    }

    /// The way a trial's line tries.
    package static func way(ofTrial line: String) -> CheckResult.WayKind? {
        if line.hasPrefix("  by script") { return .script }
        if line.hasPrefix("  by its menu") { return .menu }
        if line.hasPrefix("  by its page") { return .page }
        if line.hasPrefix("  by the Now Playing panel") { return .panel }
        return nil
    }

    /// A trial's pause took: it plays the app again next (the line goes on).
    package static let afterPause = "    after the pause"
    /// The window state can't be tested (the line goes on with why).
    package static let notTested = "    not tested"
}
