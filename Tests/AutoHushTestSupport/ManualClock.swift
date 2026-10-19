import Foundation

/// A clock that moves only when a test moves it, for code that takes its
/// time from a `() -> Date`.
package final class ManualClock: Sendable {
    private let current: Locked<Date>

    package init(start: Date = Date(timeIntervalSinceReferenceDate: 0)) {
        current = Locked(start)
    }

    package var now: Date { current.value }

    package func advance(by seconds: TimeInterval) {
        current.withLock { $0 += seconds }
    }
}
