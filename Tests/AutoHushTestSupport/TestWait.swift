import Foundation
import Testing

/// Waiting in tests for work that hops between actors, queues and the main
/// run loop. The limit is long: it only costs time when a test fails, and a
/// busy machine (the whole suite running in parallel) can take seconds for
/// what usually takes milliseconds. The main actor is the busiest: the
/// whole quick suite keeps it at work for about ten seconds, and a wait for
/// main-actor work queues behind the rest (2026-10-19: 10 s was too short).
/// `AUTOHUSH_TEST_WAIT` (seconds) makes it longer: CI's runner, several
/// times slower than the VMs, sets 90 (2026-10-21: waits of 30 s ran out
/// there).
package enum TestWait {
    package static let limit: Duration = .seconds(seconds)

    /// 30, or `AUTOHUSH_TEST_WAIT` when it's longer.
    private static let seconds = max(30, ProcessInfo.processInfo.environment["AUTOHUSH_TEST_WAIT"].flatMap(Int.init) ?? 0)

    /// The suites' limit on each test: a minute, room for two waits; longer
    /// with longer waits.
    package static let testMinutes = (2 * seconds + 59) / 60

    /// Polls `condition` on the caller's actor until it holds. Once `limit`
    /// has passed, the test fails at the caller's line, so a wait checks its
    /// condition even when nothing after it does.
    package static func until(
        isolation: isolated any Actor? = #isolation,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ condition: () async -> Bool
    ) async {
        let deadline = ContinuousClock.now + limit
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                timedOut(at: sourceLocation)
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// `limit` from now, for waits that poll from a queue or a lock.
    package static var deadline: Date { Date().addingTimeInterval(TimeInterval(limit.components.seconds)) }

    /// `limit` from now, for a semaphore's wait: a test expects `.success`,
    /// so a step that never comes fails it instead of hanging the run.
    package static var dispatchDeadline: DispatchTime { .now() + .seconds(Int(limit.components.seconds)) }

    /// A wait's condition didn't hold in time (`limit`, or `deadline` for a
    /// wait that polls from a queue or a lock): the test fails at the
    /// caller's line.
    package static func timedOut(at sourceLocation: SourceLocation) {
        Issue.record("Waited \(limit) and the condition never held", sourceLocation: sourceLocation)
    }
}

extension Trait where Self == TimeLimitTrait {
    /// Each test's time limit, as long as two of its waits (`TestWait`).
    package static var waitsTimeLimit: Self { .timeLimit(.minutes(TestWait.testMinutes)) }
}
