import Foundation

// One of playercheck's one-line answers, a tab between fields: the helper
// writes it with its `line`, and AutoHush and the Player Check app read it
// with its `init?(line:)`, so neither side can drift.

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
