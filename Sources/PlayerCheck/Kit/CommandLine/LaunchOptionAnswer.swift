import Foundation

/// --launch-option <app>: the launch option it needs, and whether it runs
/// with it: "<option, or nothing>\t<yes|no|not running>".
package struct LaunchOptionAnswer: OneLineAnswer {
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
        let fields = Self.fields(of: line.trimmingCharacters(in: .newlines))
        guard fields.count == 2 else { return nil }
        self.init(option: fields[0].isEmpty ? nil : fields[0], running: Running(rawValue: fields[1]))
    }
}
