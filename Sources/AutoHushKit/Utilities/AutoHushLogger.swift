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

    private func write(_ level: LogLevel?, _ message: LogMessage) {
        let text = message.text
        system.debug("\(text, privacy: .public)")
        guard let level else { return }
        LogFile.shared?.append(LogEntry(date: Date(), level: level, category: category, message: text))
    }
}

/// An error as the log says it: in English, as every logged line is, never
/// in the user's language (an error's `localizedDescription` would be).
package protocol LoggableError: Error {
    /// What went wrong, in English.
    var logDescription: String { get }
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
    let text: String

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

        /// An error, in English (`LogMessage.englishDescription(of:)`).
        package mutating func appendInterpolation(_ error: any Error, privacy: LogPrivacy = .public) {
            append(LogMessage.englishDescription(of: error), privacy)
        }

        private mutating func append(_ value: String, _ privacy: LogPrivacy) {
            text += privacy == .public ? value : "<private>"
        }
    }

    /// What `error` says, in English: AutoHush's own errors in their words
    /// (`LoggableError`); macOS's by their domain and code, which its words
    /// would put in the user's language, with a name for the common network
    /// ones; any other Swift error by its type and case.
    package static func englishDescription(of error: any Error) -> String {
        if let error = error as? any LoggableError { return error.logDescription }
        let cocoa = error as NSError
        guard type(of: error as Any) is NSError.Type || appleDomains.contains(cocoa.domain) else {
            return String(describing: error)
        }
        var text = "\(cocoa.domain) error \(cocoa.code)"
        if cocoa.domain == NSURLErrorDomain, let name = networkErrorNames[cocoa.code] { text += " (\(name))" }
        if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? any Error {
            text += ", from \(englishDescription(of: underlying))"
        }
        return text
    }

    /// The domains of the errors Swift's own types stand for (`URLError`,
    /// `CocoaError`, `POSIXError`).
    private static let appleDomains: Set<String> = [NSURLErrorDomain, NSCocoaErrorDomain, NSPOSIXErrorDomain, NSOSStatusErrorDomain]
    private static let networkErrorNames: [Int: String] = [
        NSURLErrorTimedOut: "timed out",
        NSURLErrorCannotFindHost: "host not found",
        NSURLErrorCannotConnectToHost: "can't connect to the host",
        NSURLErrorNetworkConnectionLost: "the connection was lost",
        NSURLErrorNotConnectedToInternet: "not connected to the Internet",
        NSURLErrorSecureConnectionFailed: "the secure connection failed",
        NSURLErrorCancelled: "cancelled",
    ]
}
