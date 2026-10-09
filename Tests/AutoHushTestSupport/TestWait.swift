import Foundation

/// Waiting in tests for work that hops between actors, queues and the main
/// run loop. The limit is long: it only costs time when a test fails, and a
/// busy machine (the whole suite running in parallel) can take seconds for
/// what usually takes milliseconds.
package enum TestWait {
    package static let limit: Duration = .seconds(10)

    /// Polls `condition` on the caller's actor until it holds, or `limit`
    /// has passed (the test's own `#expect` then fails).
    package static func until(
        isolation: isolated (any Actor)? = #isolation,
        _ condition: () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + limit
        while !(await condition()), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// `limit` from now, for waits that poll from a queue or a lock.
    package static var deadline: Date { Date().addingTimeInterval(TimeInterval(limit.components.seconds)) }
}
