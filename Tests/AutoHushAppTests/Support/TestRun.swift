import Foundation
import Testing

/// How this run of the tests was asked for.
enum TestRun {
    /// `AUTOHUSH_QUICK_TESTS=1` leaves out the tests that can be slow (those
    /// opening real disk images); a release always runs every test.
    static let quick = ProcessInfo.processInfo.environment["AUTOHUSH_QUICK_TESTS"] == "1"
}

extension Trait where Self == ConditionTrait {
    /// A test that can take seconds, left out of quick runs.
    static var slow: Self {
        .enabled(if: !TestRun.quick, "slow: left out while AUTOHUSH_QUICK_TESTS=1")
    }
}
