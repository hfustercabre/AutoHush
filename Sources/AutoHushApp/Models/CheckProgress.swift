import Foundation
import CheckedPlayers

/// How far a check has got, from its report's lines as they come: the part
/// it's in, the window state it has the app in and what it does there, what
/// it asks of the user, and whether it blocks the mouse and keyboard.
/// playercheck's report is English and only read here: what's shown is
/// AutoHush's own words for it.
struct CheckProgress: Equatable {
    enum Stage: Equatable {
        case reading, permissions, playing, movingWindow, readingPage, testing, finishing
    }

    /// A way being tried in the current window state.
    enum Activity: Equatable {
        case moving
        case pausing(CheckResult.WayKind)
        case playingAgain(CheckResult.WayKind)
        /// The state can't be tested (no other desktop, say).
        case untested
    }

    /// What the check waits for the user to do.
    enum Request: Equatable {
        /// Start the app playing, within `minutes`.
        case play(minutes: Int)
        /// Pause it with its own Pause, within `minutes` (to learn its page's button).
        case pause(minutes: Int)
        case allowAccessibility(minutes: Int)

        var minutes: Int {
            switch self {
            case .play(let minutes), .pause(let minutes), .allowAccessibility(let minutes): minutes
            }
        }
    }

    struct WindowStep: Equatable {
        let index: Int
        let count: Int
        let state: CheckResult.WindowState?
    }

    private(set) var stage = Stage.reading
    private(set) var windowStep: WindowStep?
    private(set) var activity: Activity?
    private(set) var request: Request?
    /// When the request came, for the time left.
    private(set) var requestSince: Date?
    /// From playercheck's "blocked" line until it says they're free again.
    private(set) var inputBlocked = false

    /// The mouse and keyboard are blocked now: not while the check asks
    /// something, when they're the user's again.
    var blocksInput: Bool { inputBlocked && request == nil }

    mutating func add(_ line: String, at date: Date = Date()) {
        guard !line.isEmpty else { return }
        if !line.hasPrefix(" ") {
            // A heading: a new part of the report, which ends any request.
            request = nil
            stage = Self.stage(ofHeading: line) ?? stage
            return
        }
        if line.hasPrefix("  waiting: ") {
            let text = line.dropFirst("  waiting: ".count)
            let minutes = Self.minutes(in: String(text)) ?? 2
            request = text.hasPrefix("start playing") ? .play(minutes: minutes)
                : text.hasPrefix("pause ") ? .pause(minutes: minutes)
                : text.hasPrefix("allow Accessibility") ? .allowAccessibility(minutes: minutes) : request
            requestSince = date
        } else if ["  it plays", "  it paused", "  it didn't", "  stopped", "  Accessibility:"].contains(where: line.hasPrefix) {
            request = nil
        }
        if line.hasPrefix("  your clicks, scrolling and keys are blocked") { inputBlocked = true }
        if line.hasPrefix("  mouse and keyboard free again") { inputBlocked = false }
        if line.hasPrefix("  State "), let step = Self.windowStep(in: line) {
            windowStep = step
            activity = .moving
        } else if line.hasPrefix("  by "), let way = Self.way(in: line) {
            activity = .pausing(way)
        } else if line.hasPrefix("    after the pause"), case .pausing(let way)? = activity {
            activity = .playingAgain(way)
        } else if line.hasPrefix("    not tested") {
            activity = .untested
        }
    }

    private static func stage(ofHeading heading: String) -> Stage? {
        switch heading {
        case "Permissions": .permissions
        case "Playing": .playing
        case "Window States": .movingWindow
        case "Page Buttons": .readingPage
        case "Press Test": .testing
        case "Ways to Control It", "Verdict": .finishing
        case "Scripting Dictionary", "Playback Menu", "Sound and Now Playing": .reading
        default: nil
        }
    }

    /// "  State 3 of 7: on another desktop".
    private static func windowStep(in line: String) -> WindowStep? {
        guard let colon = line.range(of: ": ") else { return nil }
        let numbers = line.dropFirst("  State ".count)[..<colon.lowerBound].components(separatedBy: " of ").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return WindowStep(index: numbers[0], count: numbers[1], state: windowState(named: String(line[colon.upperBound...])))
    }

    /// The window states as the report names them.
    static func windowState(named name: String) -> CheckResult.WindowState? {
        switch name {
        case "visible": .visible
        case "covered": .covered
        case "on another desktop": .otherDesktop
        case "covered on another desktop": .otherDesktopCovered
        case "full screen": .fullScreen
        case "minimized": .minimized
        case "hidden": .hidden
        default: nil
        }
    }

    /// "  by script (…)", "  by its menu", "  by its page's button", "  by the Now Playing panel".
    private static func way(in line: String) -> CheckResult.WayKind? {
        if line.hasPrefix("  by script") { return .script }
        if line.hasPrefix("  by its menu") { return .menu }
        if line.hasPrefix("  by its page") { return .page }
        if line.hasPrefix("  by the Now Playing panel") { return .panel }
        return nil
    }

    /// "(up to 2 minutes)".
    private static func minutes(in text: String) -> Int? {
        guard let start = text.range(of: "up to ") else { return nil }
        return Int(text[start.upperBound...].prefix { $0.isNumber })
    }
}
