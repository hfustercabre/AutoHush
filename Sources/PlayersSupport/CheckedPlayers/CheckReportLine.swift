import Foundation

/// The lines of playercheck's report that AutoHush and the Player Check app
/// follow a check by (their panel and its shade, `CheckProgress`; the
/// permission a test lacks; the app's ways in "Ways to Control It"): the
/// helper writes them with these, and they read them with these, so a
/// rewording can't leave either behind. The rest of the report is English
/// for whoever reads the log.
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
    enum Request: Sendable, Equatable {
        case play, pause, allowAccessibility
    }

    /// "  waiting: start playing something in Deezer; … (up to 2 minutes)":
    /// `text` starts as `request(in:)` reads it.
    static func waiting(_ text: String, minutes: Int) -> String {
        waitingPrefix + text + " (up to \(minutes) minutes)"
    }

    /// The check asks for `app` to be played, and goes on once it plays.
    package static func waitingToPlay(_ app: String, minutes: Int) -> String {
        waiting("start playing something in \(app); the test goes on as soon as it plays", minutes: minutes)
    }

    /// The check asks for `app` to be paused by its own Pause, to learn its
    /// page's Play/Pause from what changes on it.
    package static func waitingToPause(_ app: String, minutes: Int) -> String {
        waiting("pause \(app) yourself (its own Pause, anywhere): the check learns its page's Play/Pause from what changes on it",
                minutes: minutes)
    }

    /// The check asks for Accessibility for `holder`, the app it runs in.
    package static func waitingForAccessibility(_ holder: String, minutes: Int) -> String {
        waiting("allow Accessibility for \(holder) in System Settings; the check goes on as soon as it's allowed", minutes: minutes)
    }

    /// The request a "  waiting: " line makes, and its minutes; `nil` for any other line.
    static func request(in line: String) -> (request: Request?, minutes: Int?)? {
        guard line.hasPrefix(waitingPrefix) else { return nil }
        let text = line.dropFirst(waitingPrefix.count)
        let request: Request? = text.hasPrefix("start playing") ? .play
            : text.hasPrefix("pause ") ? .pause
            : text.hasPrefix("allow Accessibility") ? .allowAccessibility : nil
        let minutes = text.range(of: "up to ").flatMap { Int(text[$0.upperBound...].prefix { $0.isNumber }) }
        return (request, minutes)
    }

    private static let waitingPrefix = "  waiting: "

    /// The text a "  waiting: " line asks, as the helper words it (up to
    /// its minutes); `nil` for any other line.
    package static func requestText(in line: String) -> String? {
        line.hasPrefix(waitingPrefix) ? String(line.dropFirst(waitingPrefix.count)) : nil
    }

    /// Lines that answer a request: it plays, it paused, it didn't, the
    /// check stopped, Accessibility was answered.
    static let answers = ["  it plays", "  it paused", "  it didn't", "  stopped", "  \(Permission.accessibility.name):"]

    // MARK: Permissions

    /// A permission a test needs, as its lines name it.
    package enum Permission: Equatable, Sendable {
        case accessibility, audioRecording
        /// Automation for the app named `app`.
        case automation(app: String)

        package var name: String {
            switch self {
            case .accessibility: "Accessibility"
            case .audioRecording: "Audio Recording"
            case .automation(let app): "Automation for \(app)"
            }
        }

        /// The permission `name` names; older checks called Audio Recording
        /// "System Audio Recording".
        init?(name: String) {
            if name == Permission.accessibility.name {
                self = .accessibility
            } else if name.hasSuffix(Permission.audioRecording.name) {
                self = .audioRecording
            } else if name.hasPrefix(Self.automationPrefix), name.count > Self.automationPrefix.count {
                self = .automation(app: String(name.dropFirst(Self.automationPrefix.count)))
            } else {
                return nil
            }
        }

        private static let automationPrefix = "Automation for "
    }

    /// How a permission stands for a test, after its name.
    package enum PermissionAnswer: String, Sendable {
        case allowed, notAllowed = "not allowed", notAnswered = "not answered"
    }

    /// "  Accessibility: allowed".
    package static func permission(_ permission: Permission, _ answer: PermissionAnswer) -> String {
        Self.permission(permission, answer.rawValue)
    }

    /// "  Audio Recording: not used (…)": a permission's line saying more.
    package static func permission(_ permission: Permission, _ text: String) -> String {
        "  \(permission.name): \(text)"
    }

    /// The permission a line says is missing (not allowed, or not answered);
    /// `nil` for any other line.
    package static func missingPermission(in line: String) -> Permission? {
        guard line.hasPrefix("  "), let colon = line.range(of: ": ") else { return nil }
        let answer = PermissionAnswer(rawValue: String(line[colon.upperBound...]))
        guard answer == .notAllowed || answer == .notAnswered else { return nil }
        return Permission(name: String(line[..<colon.lowerBound].dropFirst(2)))
    }

    /// "Not checked: <why>": a test that didn't start, with nothing moved or
    /// pressed (`CheckExitStatus.permissionMissing`), and why.
    package static func notChecked(_ why: String) -> String { notCheckedPrefix + why }

    /// The why of a "Not checked: " line; `nil` for any other line.
    package static func notChecked(in line: String) -> String? {
        line.hasPrefix(notCheckedPrefix) ? String(line.dropFirst(notCheckedPrefix.count)) : nil
    }

    private static let notCheckedPrefix = "Not checked: "

    /// The mouse and keyboard are blocked from this line (it goes on with why).
    package static let blocked = "  your clicks, scrolling and keys are blocked"
    /// And free from this one (it may go on with why).
    package static let free = "  mouse and keyboard free again"

    /// "  State 3 of 7: on another desktop".
    package static func windowState(_ index: Int, of count: Int, _ state: CheckResult.WindowState) -> String {
        "  State \(index) of \(count): \(state.title)"
    }

    /// The window state a "  State n of m: …" line says.
    static func windowState(in line: String) -> (index: Int, count: Int, state: CheckResult.WindowState?)? {
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
    static func way(ofTrial line: String) -> CheckResult.WayKind? {
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

    // MARK: Ways to Control It

    /// A way's mark in its line under "Ways to Control It": it paused and
    /// played the app again in every window state tested, in some, in none
    /// (or it isn't there), found but not tried, not checked.
    package enum WayMark: String, CaseIterable, Sendable {
        case works = "✓", some = "⚠", none = "✗", notTried = "?", notChecked = "–"
    }

    /// What a way's line starts with, after its mark: "AppleScript",
    /// "Playback menu", "Page button", "Now Playing panel" (each may go on
    /// before its colon: "Playback menu “Controls”").
    package static func wayTitle(_ way: CheckResult.WayKind) -> String {
        switch way {
        case .script: "AppleScript"
        case .menu: "Playback menu"
        case .page: "Page button"
        case .panel: "Now Playing panel"
        }
    }

    /// "  ✓ AppleScript: …": `text` starts with the way's title.
    package static func way(_ mark: WayMark, _ text: String) -> String { "  \(mark.rawValue) \(text)" }

    /// A way's line: its mark, the way its title names, its title (up to
    /// its first ": ") and what follows; `nil` for any other line.
    package static func way(in line: String) -> (mark: WayMark, way: CheckResult.WayKind?, title: String, detail: String)? {
        guard line.hasPrefix("  "), !line.hasPrefix(wayStateIndent) else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let mark = text.first.flatMap({ WayMark(rawValue: String($0)) }) else { return nil }
        let rest = text.dropFirst().trimmingCharacters(in: .whitespaces)
        let colon = rest.range(of: ": ")
        let title = colon.map { String(rest[..<$0.lowerBound]) } ?? rest
        return (mark, CheckResult.WayKind.allCases.first { title.hasPrefix(wayTitle($0)) }, title, colon.map { String(rest[$0.upperBound...]) } ?? "")
    }

    /// "      ✗ covered: why", "      – hidden: not tested (why)": under a
    /// way's line, a window state it failed in (✗), or wasn't tested in (–,
    /// "window states" for all of them).
    package static func wayState(_ mark: WayMark, _ state: String, _ why: String) -> String {
        "\(wayStateIndent)\(mark.rawValue) \(state): \(why)"
    }

    /// A window state's line under a way: whether the way failed there, the
    /// state as named, and why; `nil` for any other line.
    package static func wayState(in line: String) -> (failed: Bool, state: String, why: String)? {
        guard line.hasPrefix(wayStateIndent) else { return nil }
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let mark = text.first.flatMap({ WayMark(rawValue: String($0)) }), let colon = text.range(of: ": ") else { return nil }
        let state = text[text.index(after: text.startIndex)..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        return (mark == .none, state, String(text[colon.upperBound...]))
    }

    private static let wayStateIndent = "      "

    /// What the AppleScript line says of commands not of the supported
    /// scriptable players' kind: the Player Check app offers no press by
    /// them before a check tried them.
    package static let unlikeScriptablePlayers = "not as the supported scriptable players"
}
