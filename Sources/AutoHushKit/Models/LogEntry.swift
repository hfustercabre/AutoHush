import Foundation

/// How much a logged line matters, from least to most (debug lines are
/// never kept: see `AutoHushLogger`).
package enum LogLevel: String, Sendable, CaseIterable, Comparable {
    case info, notice, error, fault

    /// Something went wrong: an error or a fault.
    package var isProblem: Bool { self == .error || self == .fault }

    package static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// One line of AutoHush's log (`LogFile`).
package struct LogEntry: Equatable, Hashable, Sendable {
    package let date: Date
    package let level: LogLevel
    /// The logger's category, e.g. "PlaybackArbiter".
    package let category: String
    /// The line, its private values left out.
    package let message: String

    package init(date: Date, level: LogLevel, category: String, message: String) {
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}
