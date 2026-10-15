import Foundation
import OSLog

/// AutoHush's logger. Each line goes to AutoHush's own log of the last 24
/// hours (`LogFile`, when the app keeps one: not in tools or tests), its
/// debug lines aside, and to macOS's log at the debug level only, which
/// macOS shows to a live `log stream --level debug` and never keeps on disk.
/// Private values are left out of both ("<private>").
package struct AutoHushLogger: Sendable {
    /// The app's bundle identifier, used as the unified-logging subsystem.
    package static let subsystem = "com.autohush.AutoHush"

    package let category: String
    private let system: Logger

    package init(category: String) {
        self.category = category
        system = Logger(subsystem: Self.subsystem, category: category)
    }

    /// Only for a live `log stream`: not in AutoHush's log.
    package func debug(_ message: LogMessage) { write(nil, message) }
    package func info(_ message: LogMessage) { write(.info, message) }
    package func notice(_ message: LogMessage) { write(.notice, message) }
    package func error(_ message: LogMessage) { write(.error, message) }
    package func fault(_ message: LogMessage) { write(.fault, message) }

    private func write(_ level: LogLevel?, _ message: LogMessage) {
        let text = message.text
        system.debug("\(text, privacy: .public)")
        guard let level else { return }
        LogFile.shared?.append(LogEntry(date: Date(), level: level, category: category, message: text))
    }
}

/// How a logged value shows: as it is, or left out ("<private>").
package enum LogPrivacy: Sendable {
    case `public`
    case `private`
}

/// A logged line, written as macOS's logger takes it: `"… \(value, privacy:
/// .public)"`. Numbers and Booleans show unless marked private; anything
/// else is left out unless marked public, as macOS's own logger does.
package struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    package let text: String

    package init(stringLiteral value: String) {
        text = value
    }

    package init(stringInterpolation: Interpolation) {
        text = stringInterpolation.text
    }

    package struct Interpolation: StringInterpolationProtocol {
        var text = ""

        package init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + 16 * interpolationCount)
        }

        package mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        package mutating func appendInterpolation<Value: CustomStringConvertible>(_ value: Value,
                                                                                privacy: LogPrivacy = .private) {
            append(value.description, privacy)
        }

        package mutating func appendInterpolation<Value: BinaryInteger>(_ value: Value, privacy: LogPrivacy = .public) {
            append(value.description, privacy)
        }

        package mutating func appendInterpolation<Value: BinaryFloatingPoint & CustomStringConvertible>(_ value: Value,
                                                                                                     privacy: LogPrivacy = .public) {
            append(value.description, privacy)
        }

        package mutating func appendInterpolation(_ value: Bool, privacy: LogPrivacy = .public) {
            append(value.description, privacy)
        }

        private mutating func append(_ value: String, _ privacy: LogPrivacy) {
            text += privacy == .public ? value : "<private>"
        }
    }
}
