import Foundation

// One of playercheck's one-line answers, a tab between fields: the helper
// writes it with its `line`, and AutoHush and the Player Check app read it
// with its `init?(line:)`, so neither side can drift.

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
