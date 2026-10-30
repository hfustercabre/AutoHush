import Foundation

/// Waits that grow while something keeps failing.
package enum Backoff {
    /// The wait after `failures` failures in a row: the range's lower bound
    /// after the first (or none), doubling with each one more, at most its
    /// upper bound.
    package static func doubling(afterFailures failures: Int, within waits: ClosedRange<TimeInterval>) -> TimeInterval {
        min(waits.lowerBound * pow(2, Double(max(failures - 1, 0))), waits.upperBound)
    }
}
