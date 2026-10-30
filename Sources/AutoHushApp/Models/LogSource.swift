import Foundation
import AutoHushKit

/// Where the logs window reads AutoHush's log: `LogFile`; tests stand in.
protocol LogSource: AnyObject, Sendable {
    func entries(since date: Date) async -> [LogEntry]
    func observe(_ handler: @escaping @Sendable (LogEntry) -> Void) -> UUID
    func stopObserving(_ token: UUID)
}

extension LogFile: LogSource {}
