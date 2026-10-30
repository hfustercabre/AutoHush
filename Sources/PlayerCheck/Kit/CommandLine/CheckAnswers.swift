import Foundation
import CheckedPlayers

// playercheck's one-line answers, a tab between fields: the helper writes
// each with its `line`, and AutoHush and the Player Check app read it with
// its `init?(line:)`, so neither side can drift.

/// An app macOS keeps in Now Playing, a line of --now-playing-list:
/// "<bundle ID>\t<pid>\t<state>\t<1 if active>\t<name>". The list ends with
/// the active one's process (`activeLine`).
package struct NowPlayingListLine: Equatable, Sendable {
    /// Ready for Now Playing, never said it plays.
    package static let registered = "Registered"
    /// Gone since the time --since gave.
    package static let removed = "Removed"
    /// What a playing one last reported.
    package static let playing = "Playing"

    package var bundleID: String
    package var pid: pid_t
    /// Its last state as macOS's log says it ("Playing", "Paused"…),
    /// `registered` or `removed`.
    package var state: String
    /// The active one: the Now Playing app.
    package var isActive: Bool
    var name: String

    package init(bundleID: String, pid: pid_t, state: String, isActive: Bool, name: String) {
        self.bundleID = bundleID
        self.pid = pid
        self.state = state
        self.isActive = isActive
        self.name = name
    }

    package var line: String { [bundleID, String(pid), state, isActive ? "1" : "0", name].joined(separator: "\t") }

    /// `nil` for the active line, or one that isn't an app's.
    package init?(line: some StringProtocol) {
        let fields = String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 4, !fields[0].hasPrefix("#"), let pid = pid_t(fields[1]) else { return nil }
        self.init(bundleID: fields[0], pid: pid, state: fields[2], isActive: fields[3] == "1", name: fields.count > 4 ? fields[4] : "")
    }

    /// The list's last line: the Now Playing app's process (0 for none, -1
    /// when MediaRemote didn't answer).
    package static func activeLine(_ pid: pid_t) -> String { activePrefix + String(pid) }

    /// The process an active line names; `nil` for any other line.
    package static func active(in line: some StringProtocol) -> pid_t? {
        guard line.hasPrefix(activePrefix) else { return nil }
        return pid_t(line.dropFirst(activePrefix.count))
    }

    private static let activePrefix = "#active\t"
}

/// Why an app can be in Now Playing, a line of --now-playing-reasons:
/// "<path>\t<reason>\t<interface>\t<switches>\t<kind>\t<browser>", each
/// empty when none.
package struct NowPlayingReasonsLine: Equatable, Sendable {
    /// The kind of interface `interface` names, for whoever reads the line
    /// (its name is for people).
    package enum InterfaceKind: String, Sendable {
        case electron, cef, flutter, chromiumWebApp
    }

    package var path: String
    /// What lets it be in Now Playing (`NowPlayingReason`); `nil` when
    /// nothing shows it can.
    package var reason: String?
    /// What hides its interface until a switch is on ("Electron 38.4.0",
    /// "Flutter", "Google Chrome web app"…).
    package var interface: String?
    /// The switches a check turns on for it, in order ("Electron's switch,
    /// else VoiceOver's switch").
    package var switches: String?
    package var kind: InterfaceKind?
    /// A Chromium browser's web app's browser, as its bundle names it
    /// ("Google Chrome").
    package var browser: String?

    package init(path: String, reason: String?, interface: String? = nil, switches: String? = nil, kind: InterfaceKind? = nil,
                 browser: String? = nil) {
        self.path = path
        self.reason = reason
        self.interface = interface
        self.switches = switches
        self.kind = kind
        self.browser = browser
    }

    package var line: String {
        [path, reason ?? "", interface ?? "", switches ?? "", kind?.rawValue ?? "", browser ?? ""].joined(separator: "\t")
    }

    package init?(line: some StringProtocol) {
        let fields = String(line).split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2, !fields[0].isEmpty else { return nil }
        let field = { (index: Int) in index < fields.count && !fields[index].isEmpty ? fields[index] : nil }
        self.init(path: fields[0], reason: field(1), interface: field(2), switches: field(3), kind: field(4).flatMap(InterfaceKind.init),
                  browser: field(5))
    }
}

/// --launch-option <app>: the launch option it needs, and whether it runs
/// with it: "<option, or nothing>\t<yes|no|not running>".
package struct LaunchOptionAnswer: Equatable, Sendable {
    package enum Running: String, Sendable {
        case yes, no, notRunning = "not running"
    }

    /// `nil` when it needs none.
    package var option: String?
    /// `nil` when it needs none.
    package var running: Running?

    package init(option: String?, running: Running?) {
        self.option = option
        self.running = running
    }

    package var line: String { [option ?? "", option == nil ? "" : running?.rawValue ?? ""].joined(separator: "\t") }

    package init?(line: some StringProtocol) {
        let fields = line.trimmingCharacters(in: .newlines).components(separatedBy: "\t")
        guard fields.count == 2 else { return nil }
        self.init(option: fields[0].isEmpty ? nil : fields[0], running: Running(rawValue: fields[1]))
    }
}

/// --window-state <app>: the state its main window is in now.
package enum WindowStateAnswer: Equatable, Sendable {
    case state(CheckResult.WindowState)
    case noWindow
    case notRunning

    /// The state, when it has a window.
    package var windowState: CheckResult.WindowState? {
        if case .state(let state) = self { state } else { nil }
    }

    package var line: String {
        switch self {
        case .state(let state): state.title
        case .noWindow: "no window"
        case .notRunning: "not running"
        }
    }

    /// `nil` for anything else (`AppQuery.noApp`).
    package init?(line: some StringProtocol) {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let state = CheckResult.WindowState.allCases.first(where: { $0.title == text }) {
            self = .state(state)
        } else if let answer = [WindowStateAnswer.noWindow, .notRunning].first(where: { $0.line == text }) {
            self = answer
        } else {
            return nil
        }
    }
}
