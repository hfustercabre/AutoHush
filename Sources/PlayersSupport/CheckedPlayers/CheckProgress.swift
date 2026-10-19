import Foundation

/// How far a check has got, from its report's lines as they come: the part
/// it's in, the window state it has the app in and what it does there, what
/// it asks of the user, and whether it blocks the mouse and keyboard.
/// playercheck's report is English: the lines followed here are the ones it
/// writes with `CheckReportLine`, and what's shown is the reader's own
/// words (AutoHush's Add an App…, the Player Check app's panel).
package struct CheckProgress: Equatable, Sendable {
    package enum Stage: Equatable, Sendable {
        case reading, permissions, playing, movingWindow, readingPage, testing, finishing
    }

    /// A way being tried in the current window state.
    package enum Activity: Equatable, Sendable {
        case moving
        case pausing(CheckResult.WayKind)
        case playingAgain(CheckResult.WayKind)
        /// The state can't be tested (no other desktop, say).
        case untested
    }

    /// What the check waits for the user to do.
    package enum Request: Equatable, Sendable {
        /// Start the app playing, within `minutes`.
        case play(minutes: Int)
        /// Pause it with its own Pause, within `minutes` (to learn its page's button).
        case pause(minutes: Int)
        case allowAccessibility(minutes: Int)

        package var minutes: Int {
            switch self {
            case .play(let minutes), .pause(let minutes), .allowAccessibility(let minutes): minutes
            }
        }
    }

    package struct WindowStep: Equatable, Sendable {
        package let index: Int
        package let count: Int
        package let state: CheckResult.WindowState?
    }

    package private(set) var stage = Stage.reading
    package private(set) var windowStep: WindowStep?
    package private(set) var activity: Activity?
    package private(set) var request: Request?
    /// When the request came, for the time left.
    package private(set) var requestSince: Date?
    /// From playercheck's "blocked" line until it says they're free again.
    private(set) var inputBlocked = false

    package init() {}

    /// The mouse and keyboard are blocked now: not while the check asks
    /// something, when they're the user's again.
    package var blocksInput: Bool { inputBlocked && request == nil }

    package mutating func add(_ line: String, at date: Date = Date()) {
        guard !line.isEmpty else { return }
        if !line.hasPrefix(" ") {
            // A heading: a new part of the report, which ends any request.
            request = nil
            stage = CheckReportLine.Heading(rawValue: line).map(Self.stage(of:)) ?? stage
            return
        }
        if let (asked, minutes) = CheckReportLine.request(in: line) {
            let minutes = minutes ?? 2
            switch asked {
            case .play?: request = .play(minutes: minutes)
            case .pause?: request = .pause(minutes: minutes)
            case .allowAccessibility?: request = .allowAccessibility(minutes: minutes)
            case nil: break
            }
            requestSince = date
        } else if CheckReportLine.answers.contains(where: line.hasPrefix) {
            request = nil
        }
        if line.hasPrefix(CheckReportLine.blocked) { inputBlocked = true }
        if line.hasPrefix(CheckReportLine.free) { inputBlocked = false }
        if let step = CheckReportLine.windowState(in: line) {
            windowStep = WindowStep(index: step.index, count: step.count, state: step.state)
            activity = .moving
        } else if let way = CheckReportLine.way(ofTrial: line) {
            activity = .pausing(way)
        } else if line.hasPrefix(CheckReportLine.afterPause), case .pausing(let way)? = activity {
            activity = .playingAgain(way)
        } else if line.hasPrefix(CheckReportLine.notTested) {
            activity = .untested
        }
    }

    private static func stage(of heading: CheckReportLine.Heading) -> Stage {
        switch heading {
        case .permissions: .permissions
        case .playing: .playing
        case .windowStates: .movingWindow
        case .page: .readingPage
        case .pressTest: .testing
        case .ways, .verdict: .finishing
        case .scripting, .menu, .sound: .reading
        }
    }
}
