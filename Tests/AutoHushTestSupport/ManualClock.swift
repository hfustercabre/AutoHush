import Foundation

/// A clock that moves only when a test moves it, for code that takes its
/// time from a `() -> Date`.
package final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    package init(start: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        current = start
    }

    package var now: Date { lock.withLock { current } }

    package func advance(by seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}
